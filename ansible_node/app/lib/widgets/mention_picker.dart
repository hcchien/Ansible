import 'dart:async';

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

  void record(DiscoveredActor actor) {
    if (actor.did.trim().isEmpty) return;
    _tokenByDid[actor.did.trim()] = mentionToken(actor);
  }

  List<String> activeDids(String content, {String? excludingDid}) {
    final excluded = excludingDid?.trim();
    return _tokenByDid.entries
        .where(
          (entry) =>
              entry.key != excluded && _containsToken(content, entry.value),
        )
        .map((entry) => entry.key)
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
  final handle = actor.handle?.trim().replaceFirst(RegExp(r'^@'), '');
  return '@${handle == null || handle.isEmpty ? actor.did.trim() : handle}';
}

void insertMention(TextEditingController controller, DiscoveredActor actor) {
  final token = mentionToken(actor);
  final value = controller.value;
  final start = value.selection.isValid
      ? value.selection.start
      : value.text.length;
  final end = value.selection.isValid ? value.selection.end : value.text.length;
  final prefix = start > 0 && !RegExp(r'\s').hasMatch(value.text[start - 1])
      ? ' '
      : '';
  final suffix =
      end < value.text.length && RegExp(r'\s').hasMatch(value.text[end])
      ? ''
      : ' ';
  final replacement = '$prefix$token$suffix';
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
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.alternate_email, size: 18),
                  hintText: context.uiCopy(
                    zh: '搜尋名稱或 @handle',
                    en: 'Search name or @handle',
                  ),
                  border: const OutlineInputBorder(),
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
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(actor.label),
                        subtitle: Text(
                          actor.handle?.trim().isNotEmpty == true
                              ? '@${actor.handle!.replaceFirst(RegExp(r'^@'), '')}'
                              : actor.did,
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
