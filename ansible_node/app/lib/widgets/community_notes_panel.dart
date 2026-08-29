import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/app_view_timeline_client.dart';
import '../services/community_notes_preferences.dart';
import '../services/forum_host_client.dart';
import '../services/ops_dispatch_service.dart';
import '../theme/ansible_design.dart';

class CommunityNotesPanel extends StatefulWidget {
  const CommunityNotesPanel({
    super.key,
    required this.targetRef,
    required this.localDid,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.appViewBaseUrl,
    this.forumHostBaseUrl,
    this.appViewClient,
    this.forumHostClient,
    this.preferencesStore =
        const SharedPreferencesCommunityNotesPreferencesStore(),
  });

  final String targetRef;
  final String localDid;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;
  final String? appViewBaseUrl;
  final String? forumHostBaseUrl;
  final AppViewTimelineClient? appViewClient;
  final ForumHostClient? forumHostClient;
  final CommunityNotesPreferencesStore preferencesStore;

  @override
  State<CommunityNotesPanel> createState() => _CommunityNotesPanelState();
}

class _CommunityNotesPanelState extends State<CommunityNotesPanel> {
  CommunityNotesBundle? _bundle;
  Map<String, Map<String, dynamic>> _statuses = const {};
  bool _loading = true;
  bool _visible = true;
  bool _preferenceLoaded = false;
  bool _collapsed = false;
  bool _submitting = false;

  String get _appViewBaseUrl =>
      widget.appViewBaseUrl ?? AppEnvironment.appViewBaseUrl;
  String get _forumHostBaseUrl =>
      widget.forumHostBaseUrl ?? AppEnvironment.defaultRelayBaseUrl;
  AppViewTimelineClient get _appViewClient =>
      widget.appViewClient ?? AppViewTimelineClient(baseUrl: _appViewBaseUrl);
  ForumHostClient get _forumHostClient =>
      widget.forumHostClient ?? ForumHostClient(baseUrl: _forumHostBaseUrl);

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final visible = await widget.preferencesStore.showCommunityNotes();
    if (!mounted) return;
    setState(() {
      _visible = visible;
      _preferenceLoaded = true;
      if (!visible) _loading = false;
    });
    if (visible) await _load();
  }

  Future<void> _load() async {
    if (_appViewBaseUrl.isEmpty && widget.appViewClient == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final bundle = await _appViewClient.fetchCommunityNotes(
        targetRef: widget.targetRef,
      );
      List<Map<String, dynamic>> statuses = const [];
      try {
        statuses = await _forumHostClient.fetchContextNoteStatuses(
          widget.targetRef,
        );
      } catch (_) {
        // Note content stays readable if the selected host is unavailable.
      }
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _statuses = {
          for (final status in statuses)
            if (status['note_id'] is String)
              status['note_id'] as String: status,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _writeNote({CommunityNote? existing}) async {
    final target = existing?.target ?? _bundle?.target;
    if (target == null) return;
    final draft = await _showNoteEditor(existing);
    if (draft == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final sources = [
        {'url': draft.url, if (draft.title.isNotEmpty) 'title': draft.title},
      ];
      final entry = existing == null
          ? CrdtOpBuilder.createContextNote(
              authorDid: widget.localDid,
              entityId: const Uuid().v4(),
              targetEntityType: target.entityType,
              targetEntityId: target.entityId,
              targetOpId: target.opId,
              targetContentHash: target.contentHash,
              body: draft.body,
              sources: sources,
            )
          : CrdtOpBuilder.updateContextNote(
              authorDid: widget.localDid,
              entityId: existing.noteId,
              targetEntityType: target.entityType,
              targetEntityId: target.entityId,
              targetOpId: target.opId,
              targetContentHash: target.contentHash,
              body: draft.body,
              sources: sources,
            );
      await widget.opsDispatchService.signAndEnqueue(entry);
      await widget.onFlushPendingOps();
      if (!mounted) return;
      _notice(
        zh: existing == null ? '社群脈絡已簽署送出' : '社群脈絡已更新',
        en: existing == null
            ? 'Community Note signed and sent'
            : 'Community Note updated',
      );
      await _load();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _withdraw(CommunityNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.uiCopy(zh: '撤回社群脈絡', en: 'Withdraw Community Note'),
        ),
        content: Text(
          context.uiCopy(
            zh: '撤回後公開頁面將不再顯示這則脈絡。',
            en: 'The note will no longer appear publicly.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.uiCopy(zh: '撤回', en: 'Withdraw')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.opsDispatchService.signAndEnqueue(
      CrdtOpBuilder.deleteContextNote(
        authorDid: widget.localDid,
        entityId: note.noteId,
      ),
    );
    await widget.onFlushPendingOps();
    if (!mounted) return;
    setState(() {
      _bundle = CommunityNotesBundle(
        target: _bundle?.target,
        notes: (_bundle?.notes ?? const [])
            .where((value) => value.noteId != note.noteId)
            .toList(),
      );
    });
  }

  Future<void> _rate(CommunityNote note) async {
    if (note.authorDid == widget.localDid) return;
    final draft = await _showRatingDialog();
    if (draft == null) return;
    final now = DateTime.now().toUtc();
    final unsigned = RateContextNoteIntent.canonicalPayload(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: _forumHostBaseUrl,
      noteId: note.noteId,
      level: draft.level,
      tags: [draft.tag],
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    setState(() => _submitting = true);
    try {
      final signed = await widget.opsDispatchService.signer.sign(
        utf8.encode(forumHostCanonicalJson(unsigned)),
      );
      await _forumHostClient.rateContextNote(
        RateContextNoteIntent(
          intentId: unsigned['intent_id']! as String,
          authorDid: widget.localDid,
          targetForumHost: _forumHostBaseUrl,
          noteId: note.noteId,
          level: draft.level,
          tags: [draft.tag],
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
          signature: signed.hex,
        ),
      );
      await _load();
      if (mounted) {
        _notice(
          zh: '評分已私密送至此 Forum Host',
          en: 'Rating sent privately to this Forum Host',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_preferenceLoaded || !_visible) return const SizedBox.shrink();
    final notes = [...?_bundle?.notes]..sort(_compareNotes);
    if (!_loading && notes.isEmpty && _bundle?.target == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('community_notes_panel'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.uiCopy(zh: '社群脈絡', en: 'Community Notes'),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.sans,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.uiCopy(
                  zh: _collapsed ? '顯示' : '隱藏',
                  en: _collapsed ? 'Show' : 'Hide',
                ),
                onPressed: () => setState(() => _collapsed = !_collapsed),
                icon: Icon(_collapsed ? Icons.expand_more : Icons.expand_less),
              ),
            ],
          ),
          if (!_collapsed) ...[
            Text(
              context.uiCopy(
                zh: '由使用者簽署並附上來源；狀態是此 Forum Host 的聚合結果，不代表全域真相。',
                en: 'Signed and sourced by users. Status is this Forum Host’s aggregate, not a universal truth.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            for (final note in notes) _noteCard(note),
            if (!_loading && notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  context.uiCopy(
                    zh: '目前沒有社群脈絡。',
                    en: 'No Community Notes yet.',
                  ),
                ),
              ),
            if (_bundle?.target != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('community_notes_add'),
                  onPressed: _submitting ? null : () => _writeNote(),
                  icon: const Icon(Icons.add_link),
                  label: Text(
                    context.uiCopy(zh: '新增附來源脈絡', en: 'Add sourced context'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _noteCard(CommunityNote note) {
    final status = _statuses[note.noteId];
    final label = _statusLabel(status?['status'] as String?);
    final highlighted = status?['status'] == 'helpful';
    final scorer = status?['scorer_id'] as String?;
    final scorerVersion = status?['scorer_version'];
    final topTags = (status?['top_tags'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value['tag']?.toString())
        .whereType<String>()
        .toList(growable: false);
    return Container(
      key: Key('community_note_${note.noteId}'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? Theme.of(
                context,
              ).colorScheme.tertiaryContainer.withValues(alpha: 0.28)
            : null,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (note.authorDid == widget.localDid)
                PopupMenuButton<String>(
                  onSelected: (value) => value == 'edit'
                      ? _writeNote(existing: note)
                      : _withdraw(note),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.uiCopy(zh: '編輯', en: 'Edit')),
                    ),
                    PopupMenuItem(
                      value: 'withdraw',
                      child: Text(context.uiCopy(zh: '撤回', en: 'Withdraw')),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note.body),
          if (scorer != null || topTags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (scorer != null)
                  '$scorer${scorerVersion == null ? '' : ' v$scorerVersion'}',
                if (topTags.isNotEmpty) topTags.join(' · '),
              ].join(' · '),
              key: Key('community_note_provenance_${note.noteId}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          for (final source in note.sources)
            TextButton.icon(
              onPressed: () {
                final uri = Uri.tryParse(source.url);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new, size: 15),
              label: Text(
                source.title?.isNotEmpty == true ? source.title! : source.url,
              ),
            ),
          Row(
            children: [
              Text(
                '${status?['rating_count'] ?? 0} ${context.uiCopy(zh: '次評分', en: 'ratings')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              if (note.authorDid != widget.localDid)
                TextButton(
                  key: Key('community_note_rate_${note.noteId}'),
                  onPressed: _submitting ? null : () => _rate(note),
                  child: Text(
                    context.uiCopy(zh: '評估是否有幫助', en: 'Rate helpfulness'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(String? status) => switch (status) {
    'helpful' => context.uiCopy(zh: '社群認為有幫助', en: 'Rated helpful'),
    'not_helpful' => context.uiCopy(zh: '社群認為沒有幫助', en: 'Rated not helpful'),
    'disputed' => context.uiCopy(zh: '評價有分歧', en: 'Disputed'),
    'target_changed' => context.uiCopy(zh: '原內容已變更', en: 'Target changed'),
    'removed_by_host' => context.uiCopy(
      zh: '已由此 Host 隱藏',
      en: 'Hidden by this Host',
    ),
    _ => context.uiCopy(zh: '尚待更多評分', en: 'Needs more ratings'),
  };

  int _compareNotes(CommunityNote left, CommunityNote right) {
    final leftStatus = _statuses[left.noteId];
    final rightStatus = _statuses[right.noteId];
    final leftHelpful = leftStatus?['status'] == 'helpful' ? 1 : 0;
    final rightHelpful = rightStatus?['status'] == 'helpful' ? 1 : 0;
    if (leftHelpful != rightHelpful) return rightHelpful - leftHelpful;
    final leftScore = (leftStatus?['score'] as num?)?.toDouble() ?? -1;
    final rightScore = (rightStatus?['score'] as num?)?.toDouble() ?? -1;
    return rightScore.compareTo(leftScore);
  }

  Future<_NoteDraft?> _showNoteEditor(CommunityNote? existing) async {
    final body = TextEditingController(text: existing?.body ?? '');
    final source = existing == null || existing.sources.isEmpty
        ? null
        : existing.sources.first;
    final url = TextEditingController(text: source?.url ?? '');
    final title = TextEditingController(text: source?.title ?? '');
    return showDialog<_NoteDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.uiCopy(zh: '附來源的社群脈絡', en: 'Sourced Community Note'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: body,
                maxLength: 1000,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: '脈絡說明', en: 'Context'),
                ),
              ),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: context.uiCopy(
                    zh: '來源網址（HTTP/S）',
                    en: 'Source URL (HTTP/S)',
                  ),
                ),
              ),
              TextField(
                controller: title,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: context.uiCopy(
                    zh: '來源標題（選填）',
                    en: 'Source title (optional)',
                  ),
                ),
              ),
              Text(
                context.uiCopy(
                  zh: '送出後，脈絡、來源、目標版本與你的 DID 會公開。',
                  en: 'The note, sources, target revision, and your DID become public.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final parsed = Uri.tryParse(url.text.trim());
              if (body.text.trim().isEmpty ||
                  parsed == null ||
                  !['http', 'https'].contains(parsed.scheme) ||
                  parsed.host.isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _NoteDraft(
                  body.text.trim(),
                  url.text.trim(),
                  title.text.trim(),
                ),
              );
            },
            child: Text(context.uiCopy(zh: '簽署並送出', en: 'Sign and send')),
          ),
        ],
      ),
    );
  }

  Future<_RatingDraft?> _showRatingDialog() async {
    var level = 'helpful';
    var tag = 'good_sources';
    return showDialog<_RatingDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final tags = level == 'not_helpful'
              ? const [
                  'incorrect',
                  'sources_missing_or_unreliable',
                  'off_topic',
                  'opinion_or_speculation',
                  'argumentative_or_harassing',
                  'outdated',
                ]
              : const [
                  'addresses_claim',
                  'important_context',
                  'good_sources',
                  'clear',
                ];
          if (!tags.contains(tag)) tag = tags.first;
          return AlertDialog(
            title: Text(
              context.uiCopy(zh: '評估社群脈絡', en: 'Rate Community Note'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.uiCopy(
                    zh: '你的簽章評分會私密送至此 Forum Host；公眾只會看到聚合數量、原因與狀態。',
                    en: 'Your signed rating is sent privately to this Forum Host. The public sees only aggregate counts, reasons, and status.',
                  ),
                ),
                DropdownButton<String>(
                  value: level,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'helpful', child: Text('Helpful')),
                    DropdownMenuItem(
                      value: 'somewhat_helpful',
                      child: Text('Somewhat helpful'),
                    ),
                    DropdownMenuItem(
                      value: 'not_helpful',
                      child: Text('Not helpful'),
                    ),
                  ],
                  onChanged: (value) => setLocalState(() => level = value!),
                ),
                DropdownButton<String>(
                  value: tag,
                  isExpanded: true,
                  items: [
                    for (final value in tags)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: (value) => setLocalState(() => tag = value!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _RatingDraft(level, tag)),
                child: Text(context.uiCopy(zh: '簽署評分', en: 'Sign rating')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _notice({required String zh, required String en}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.uiCopy(zh: zh, en: en)),
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft(this.body, this.url, this.title);
  final String body;
  final String url;
  final String title;
}

class _RatingDraft {
  const _RatingDraft(this.level, this.tag);
  final String level;
  final String tag;
}
