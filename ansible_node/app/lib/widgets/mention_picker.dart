import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/discovery_client.dart';
import '../theme/ansible_design.dart';

typedef MentionActorSearch =
    Future<List<DiscoveredActor>> Function(String query);

/// Tracks only explicit picker selections. A typed `@handle` is display text,
/// not a trustworthy routing identity, so it never becomes a notification
/// recipient until the user selects the matching public profile.
class MentionDraft {
  final Map<String, String> _tokenByDid = {};

  String record(DiscoveredActor actor) {
    final did = actor.did.trim();
    if (did.isEmpty) return '';

    final existing = _tokenByDid[did];
    if (existing != null) return existing;

    final preferred = mentionToken(actor);
    final hasCollision = _tokenByDid.entries.any(
      (entry) =>
          entry.key != did &&
          entry.value.toLowerCase() == preferred.toLowerCase(),
    );
    final token = hasCollision
        ? _disambiguatedMentionToken(actor, preferred)
        : preferred;
    _tokenByDid[did] = token;
    return token;
  }

  List<String> activeDids(String content, {String? excludingDid}) {
    final excluded = excludingDid?.trim();
    return activeMentions(
      content,
      excludingDid: excluded,
    ).map((mention) => mention.did).toList(growable: false);
  }

  List<PostMention> activeMentions(String content, {String? excludingDid}) {
    final excluded = excludingDid?.trim();
    return _tokenByDid.entries
        .where(
          (entry) =>
              entry.key != excluded && _containsToken(content, entry.value),
        )
        .map((entry) => PostMention(did: entry.key, token: entry.value))
        .take(10)
        .toList(growable: false);
  }

  void clear() => _tokenByDid.clear();

  static bool _containsToken(String content, String token) {
    final escaped = RegExp.escape(token);
    return RegExp(
      '(^|\\s)$escaped(?=\\s|[.,!?，。！？、:;；：)]|\$)',
      caseSensitive: false,
    ).hasMatch(content);
  }
}

String mentionToken(DiscoveredActor actor) {
  final displayName = _singleLine(actor.displayName);
  if (displayName != null) return '@$displayName';

  final handle = _normalizedHandle(actor.handle);
  if (handle != null) return '@$handle';

  return '@${_shortDid(actor.did)}';
}

String _disambiguatedMentionToken(DiscoveredActor actor, String preferred) {
  final handle = _normalizedHandle(actor.handle);
  if (handle != null) return '$preferred (@$handle)';
  return '$preferred (${_shortDid(actor.did)})';
}

String? _singleLine(String? value) {
  final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _normalizedHandle(String? value) {
  final normalized = value?.trim().replaceFirst(RegExp(r'^@'), '');
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _shortDid(String value) {
  final did = value.trim();
  if (did.length <= 18) return did;
  return '${did.substring(0, 8)}…${did.substring(did.length - 6)}';
}

void insertMention(
  TextEditingController controller,
  DiscoveredActor actor, {
  String? token,
  int? replaceStart,
  int? replaceEnd,
}) {
  final resolvedToken = token?.trim().isNotEmpty == true
      ? token!.trim()
      : mentionToken(actor);
  final value = controller.value;
  final hasValidReplacement =
      replaceStart != null &&
      replaceEnd != null &&
      replaceStart >= 0 &&
      replaceEnd >= replaceStart &&
      replaceEnd <= value.text.length;
  final start = hasValidReplacement
      ? replaceStart
      : value.selection.isValid
      ? value.selection.start
      : value.text.length;
  final end = hasValidReplacement
      ? replaceEnd
      : value.selection.isValid
      ? value.selection.end
      : value.text.length;
  final prefix = start > 0 && !RegExp(r'\s').hasMatch(value.text[start - 1])
      ? ' '
      : '';
  final suffix =
      end < value.text.length && RegExp(r'\s').hasMatch(value.text[end])
      ? ''
      : ' ';
  final replacement = '$prefix$resolvedToken$suffix';
  final text = value.text.replaceRange(start, end, replacement);
  final cursor = start + replacement.length;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor),
  );
}

Future<DiscoveredActor?> showMentionPicker({
  required BuildContext context,
  MentionActorSearch? search,
  String? excludingDid,
}) {
  DiscoveryClient? fallbackClient;
  if (search == null) {
    fallbackClient = DiscoveryClient(
      appViewBaseUrl: AppEnvironment.appViewBaseUrl,
      relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
    );
  }
  final actorSearch =
      search ?? (query) => fallbackClient!.searchActors(query: query);
  return showModalBottomSheet<DiscoveredActor>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AnsibleDesign.paper,
    builder: (_) =>
        _MentionPickerSheet(search: actorSearch, excludingDid: excludingDid),
  ).whenComplete(() => fallbackClient?.close());
}

class _MentionPickerSheet extends StatefulWidget {
  const _MentionPickerSheet({required this.search, this.excludingDid});

  final MentionActorSearch search;
  final String? excludingDid;

  @override
  State<_MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends State<_MentionPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;
  bool _failed = false;
  List<DiscoveredActor> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _schedule(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _failed = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(query));
  }

  Future<void> _run(String query) async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final found = await widget.search(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = found
            .where(
              (actor) =>
                  actor.did.trim().isNotEmpty &&
                  actor.did.trim() != widget.excludingDid?.trim(),
            )
            .take(10)
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = const [];
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottom),
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.uiCopy(zh: '提及其他人', en: 'Mention someone'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('mention_search_field'),
                controller: _controller,
                autofocus: true,
                onChanged: _schedule,
                cursorColor: AnsibleDesign.accent,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  color: AnsibleDesign.ink,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AnsibleDesign.paperElev,
                  prefixIcon: const Icon(
                    Icons.alternate_email,
                    size: 18,
                    color: AnsibleDesign.inkMuted,
                  ),
                  hintText: context.uiCopy(
                    zh: '搜尋名稱或 @handle',
                    en: 'Search name or @handle',
                  ),
                  hintStyle: const TextStyle(color: AnsibleDesign.inkFaint),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AnsibleDesign.compactRadius,
                    ),
                    borderSide: const BorderSide(color: AnsibleDesign.rule),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AnsibleDesign.compactRadius,
                    ),
                    borderSide: const BorderSide(color: AnsibleDesign.rule),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AnsibleDesign.compactRadius,
                    ),
                    borderSide: const BorderSide(
                      color: AnsibleDesign.accent,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    context.uiCopy(
                      zh: '目前無法搜尋人物，請稍後再試。',
                      en: 'People search is unavailable. Try again later.',
                    ),
                    style: const TextStyle(color: AnsibleDesign.danger),
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final actor in _results)
                      ListTile(
                        key: Key('mention_actor_${actor.did}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: AnsibleDesign.accentSoft,
                          foregroundColor: AnsibleDesign.accent,
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(
                          actor.label,
                          style: const TextStyle(
                            color: AnsibleDesign.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          actor.handle?.trim().isNotEmpty == true
                              ? '@${actor.handle!.replaceFirst(RegExp(r'^@'), '')}'
                              : _shortDid(actor.did),
                          style: const TextStyle(color: AnsibleDesign.inkMuted),
                        ),
                        onTap: () => Navigator.of(context).pop(actor),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
