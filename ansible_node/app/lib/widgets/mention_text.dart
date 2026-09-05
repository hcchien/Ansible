import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../services/handle_resolver.dart';

/// Renders only explicitly resolved mentions as profile links. The signed DID
/// remains the navigation identity; display text is never used to pick a user.
class MentionText extends StatelessWidget {
  const MentionText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    required this.onOpenProfile,
    this.mentions = const [],
    this.mentionDids = const [],
    this.profileResolver,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final List<PostMention> mentions;
  final List<String> mentionDids;
  final PublicProfileResolver? profileResolver;
  final void Function(String did, String? displayName) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final immediate = _validReferences(mentions);
    return FutureBuilder<List<_ResolvedMention>>(
      initialData: immediate,
      future: _resolveReferences(immediate),
      builder: (context, snapshot) =>
          Text.rich(_buildSpan(snapshot.data ?? immediate), style: style),
    );
  }

  List<_ResolvedMention> _validReferences(Iterable<PostMention> values) {
    final seen = <String>{};
    return values
        .where(
          (mention) =>
              mention.did.startsWith('did:') &&
              mention.token.startsWith('@') &&
              _containsToken(text, mention.token) &&
              seen.add(mention.did),
        )
        .take(10)
        .map(
          (mention) => _ResolvedMention(
            did: mention.did,
            token: mention.token,
            displayName: _displayNameFromToken(mention.token),
          ),
        )
        .toList(growable: false);
  }

  Future<List<_ResolvedMention>> _resolveReferences(
    List<_ResolvedMention> immediate,
  ) async {
    final resolved = [...immediate];
    final seen = immediate.map((mention) => mention.did).toSet();
    final resolver = profileResolver ?? PublicProfileResolver.shared;
    for (final rawDid in mentionDids) {
      final did = rawDid.trim();
      if (!did.startsWith('did:') ||
          seen.contains(did) ||
          resolved.length >= 10) {
        continue;
      }
      final profile = await resolver.profileFor(did);
      final displayName = profile?.displayName?.trim();
      final handle = profile?.handle?.trim().replaceFirst(RegExp(r'^@'), '');
      final candidates = <String>[
        if (displayName != null && displayName.isNotEmpty) '@$displayName',
        if (handle != null && handle.isNotEmpty) '@$handle',
      ];
      String? token;
      for (final candidate in candidates) {
        if (_containsToken(text, candidate)) {
          token = candidate;
          break;
        }
      }
      if (token == null) continue;
      seen.add(did);
      resolved.add(
        _ResolvedMention(did: did, token: token, displayName: displayName),
      );
    }
    return resolved;
  }

  TextSpan _buildSpan(List<_ResolvedMention> references) {
    if (references.isEmpty) return TextSpan(text: text);
    final sorted = [...references]
      ..sort((left, right) => right.token.length.compareTo(left.token.length));
    final children = <InlineSpan>[];
    var cursor = 0;
    var linkIndex = 0;
    while (cursor < text.length) {
      _MentionMatch? next;
      for (final mention in sorted) {
        final match = _findToken(text, mention.token, cursor);
        if (match == null) continue;
        if (next == null || match.start < next.start) {
          next = _MentionMatch(
            start: match.start,
            end: match.end,
            mention: mention,
          );
        }
      }
      if (next == null) {
        children.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (next.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, next.start)));
      }
      final visibleToken = text.substring(next.start, next.end);
      final mention = next.mention;
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            link: true,
            label: visibleToken,
            child: GestureDetector(
              key: ValueKey('mention_profile_${mention.did}_${linkIndex++}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpenProfile(mention.did, mention.displayName),
              child: Text(
                visibleToken,
                style: style.copyWith(
                  color: linkColor,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ),
      );
      cursor = next.end;
    }
    return TextSpan(children: children);
  }
}

class _ResolvedMention {
  const _ResolvedMention({
    required this.did,
    required this.token,
    this.displayName,
  });

  final String did;
  final String token;
  final String? displayName;
}

class _MentionMatch {
  const _MentionMatch({
    required this.start,
    required this.end,
    required this.mention,
  });

  final int start;
  final int end;
  final _ResolvedMention mention;
}

_TokenRange? _findToken(String text, String token, int start) {
  final expression = RegExp(
    '(^|\\s)(${RegExp.escape(token)})(?=\\s|[.,!?，。！？、:;；：)]|\$)',
    caseSensitive: false,
  );
  final match = expression.firstMatch(text.substring(start));
  if (match == null) return null;
  final leading = match.group(1)?.length ?? 0;
  return _TokenRange(start + match.start + leading, start + match.end);
}

bool _containsToken(String text, String token) =>
    _findToken(text, token, 0) != null;

String _displayNameFromToken(String token) {
  final withoutAt = token.substring(1);
  final disambiguator = withoutAt.indexOf(' (@');
  return disambiguator < 0 ? withoutAt : withoutAt.substring(0, disambiguator);
}

class _TokenRange {
  const _TokenRange(this.start, this.end);

  final int start;
  final int end;
}
