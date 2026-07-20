import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'murmur_detail_screen.dart';
import 'posts_view_screen.dart';
import 'threads_list_screen.dart';

enum _SearchScope { all, private, circle, public }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.db,
    this.localDid,
    this.contentItems = const [],
  });

  final AppDatabase? db;
  final String? localDid;

  /// Compatibility seam for isolated previews. Product entry points use [db].
  final List<ContentItem> contentItems;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  _SearchScope _scope = _SearchScope.all;
  List<LocalSearchResult> _results = const [];
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.db != null) unawaited(_search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _queryController.text.trim();
    final results = widget.db == null ? _legacyResults(query) : _results;
    final boards = _ofKind(results, LocalSearchKind.board);
    final notes = _ofKind(results, LocalSearchKind.note);
    final murmurs = _ofKind(results, LocalSearchKind.murmur);
    final threads = [
      ..._ofKind(results, LocalSearchKind.thread),
      ..._ofKind(results, LocalSearchKind.post),
    ];
    final total = results.length;

    return AnsibleScreenScaffold(
      title: 'SEARCH',
      leadingLabel: l10n.searchBack,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: TextField(
              controller: _queryController,
              onChanged: (_) {
                setState(() {});
                _scheduleSearch();
              },
              style: const TextStyle(fontSize: 14, color: AnsibleDesign.ink),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.clear,
                        onPressed: () {
                          _queryController.clear();
                          setState(() {});
                          _scheduleSearch(immediate: true);
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                hintText: l10n.searchHint,
                filled: true,
                fillColor: AnsibleDesign.paperDeep.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AnsibleDesign.ink),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AnsibleDesign.ink),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AnsibleDesign.ink),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ScopeChip(
                  label: l10n.searchScopeAll,
                  selected: _scope == _SearchScope.all,
                  onTap: () => _setScope(_SearchScope.all),
                ),
                _ScopeChip(
                  label: l10n.searchScopeMy,
                  selected: _scope == _SearchScope.private,
                  onTap: () => _setScope(_SearchScope.private),
                ),
                _ScopeChip(
                  label: l10n.searchScopeCircle,
                  selected: _scope == _SearchScope.circle,
                  onTap: () => _setScope(_SearchScope.circle),
                ),
                _ScopeChip(
                  label: l10n.searchScopePublic,
                  selected: _scope == _SearchScope.public,
                  onTap: () => _setScope(_SearchScope.public),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Row(
              children: [
                Text(
                  _loading
                      ? context.uiCopy(
                          zh: '搜尋本機資料中…',
                          en: 'Searching this device…',
                        )
                      : l10n.searchResultCount(total),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.searchSortRelevant,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          _ResultSection(
            label: context.uiCopy(
              zh: '看板 · ${boards.length}',
              en: 'BOARDS · ${boards.length}',
            ),
            emptyLabel: context.uiCopy(
              zh: query.isEmpty ? '還沒有本機看板' : '沒有符合的看板',
              en: query.isEmpty ? 'No local boards yet' : 'No matching boards',
            ),
            rows: [
              for (final result in boards)
                _ResultRow(
                  data: _ResultData.fromLocalResult(context, result),
                  query: query,
                  onTap: () => _openResult(result),
                ),
            ],
          ),
          _ResultSection(
            label: l10n.notesSectionCount(notes.length),
            emptyLabel: query.isEmpty ? l10n.noNotesYet : l10n.noMatchingNotes,
            rows: [
              for (final result in notes)
                _ResultRow(
                  data: _ResultData.fromLocalResult(context, result),
                  query: query,
                  onTap: () => _openResult(result),
                ),
            ],
          ),
          _ResultSection(
            label: l10n.murmursSectionCount(murmurs.length),
            emptyLabel: query.isEmpty
                ? l10n.noMurmursYet
                : l10n.noMatchingMurmurs,
            rows: [
              for (final result in murmurs)
                _ResultRow(
                  data: _ResultData.fromLocalResult(context, result),
                  query: query,
                  onTap: () => _openResult(result),
                ),
            ],
          ),
          _ResultSection(
            label: l10n.threadsSectionCount(threads.length),
            emptyLabel: query.isEmpty
                ? l10n.noThreadsYet
                : l10n.noMatchingThreads,
            rows: [
              for (final result in threads)
                _ResultRow(
                  data: _ResultData.fromLocalResult(context, result),
                  query: query,
                  onTap: () => _openResult(result),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _setScope(_SearchScope scope) {
    setState(() => _scope = scope);
    _scheduleSearch(immediate: true);
  }

  void _scheduleSearch({bool immediate = false}) {
    if (widget.db == null) return;
    _debounce?.cancel();
    if (immediate) {
      unawaited(_search());
    } else {
      _debounce = Timer(const Duration(milliseconds: 180), _search);
    }
  }

  Future<void> _search() async {
    final db = widget.db;
    if (db == null) return;
    final requestId = ++_requestId;
    setState(() => _loading = true);
    final scope = switch (_scope) {
      _SearchScope.all => LocalSearchScope.all,
      _SearchScope.private => LocalSearchScope.private,
      _SearchScope.circle => LocalSearchScope.circle,
      _SearchScope.public => LocalSearchScope.public,
    };
    final results = await DriftLocalSearchRepository(
      db,
    ).search(_queryController.text, scope: scope);
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  List<LocalSearchResult> _legacyResults(String query) {
    final needle = query.toLowerCase();
    return widget.contentItems
        .where(
          (item) =>
              needle.isEmpty ||
              '${item.title ?? ''}\n${item.body}'.toLowerCase().contains(
                needle,
              ),
        )
        .map(
          (item) => LocalSearchResult(
            kind: item.mode == ContentMode.note
                ? LocalSearchKind.note
                : LocalSearchKind.murmur,
            entityId: item.id,
            title: item.title ?? '',
            body: item.body,
            authorDid: item.authorDid,
            visibility: item.visibility.name,
            localOnly: item.localOnly,
            updatedAt: item.updatedAt,
          ),
        )
        .toList();
  }

  List<LocalSearchResult> _ofKind(
    List<LocalSearchResult> results,
    LocalSearchKind kind,
  ) => results.where((result) => result.kind == kind).toList();

  Future<void> _openResult(LocalSearchResult result) async {
    final db = widget.db;
    if (db == null) return;
    switch (result.kind) {
      case LocalSearchKind.board:
        final board = await DriftBoardRepository(db).getById(result.entityId);
        if (board == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadsListScreen(
              db: db,
              board: board,
              localDid: widget.localDid,
            ),
          ),
        );
      case LocalSearchKind.thread:
      case LocalSearchKind.post:
        final threadId = result.threadId ?? result.entityId;
        final thread = await DriftThreadRepository(db).getById(threadId);
        final openingPost = result.kind == LocalSearchKind.post
            ? await DriftPostRepository(db).getById(result.entityId)
            : null;
        if (thread == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PostsViewScreen(
              db: db,
              thread: thread,
              openingPost: openingPost,
              authorDid: widget.localDid,
            ),
          ),
        );
      case LocalSearchKind.note:
      case LocalSearchKind.murmur:
        final item = await DriftContentItemRepository(
          db,
        ).getById(result.entityId);
        if (item == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MurmurDetailScreen(murmur: item),
          ),
        );
    }
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AnsibleDesign.ink : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AnsibleDesign.paper : AnsibleDesign.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.label,
    required this.emptyLabel,
    required this.rows,
  });

  final String label;
  final String emptyLabel;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(
          label,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
        ),
        AnsibleRuleGroup(
          children: rows.isEmpty ? [_EmptyResultRow(emptyLabel)] : rows,
        ),
      ],
    );
  }
}

class _EmptyResultRow extends StatelessWidget {
  const _EmptyResultRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.6,
          color: AnsibleDesign.inkMuted,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.data, required this.query, this.onTap});

  final _ResultData data;
  final String query;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  data.kindLabel,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8.5,
                    letterSpacing: 1.4,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.visibilityColor,
                  ),
                ),
                if (data.title.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AnsibleDesign.ink,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                Text(
                  data.when,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text.rich(
              _highlight(data.body, query),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _highlight(String text, String query) {
    if (query.isEmpty) return TextSpan(text: text);
    final source = text.toLowerCase();
    final needle = query.toLowerCase();
    final index = source.indexOf(needle);
    if (index < 0) return TextSpan(text: text);
    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, index)),
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            color: AnsibleDesign.ink,
            backgroundColor: AnsibleDesign.accentSoft,
          ),
        ),
        TextSpan(text: text.substring(index + query.length)),
      ],
    );
  }
}

class _ResultData {
  const _ResultData({
    required this.kindLabel,
    required this.title,
    required this.body,
    required this.when,
    required this.visibilityColor,
  });

  factory _ResultData.fromLocalResult(
    BuildContext context,
    LocalSearchResult result,
  ) {
    final kind = switch (result.kind) {
      LocalSearchKind.board => 'BRD',
      LocalSearchKind.thread => 'THRD',
      LocalSearchKind.post => 'POST',
      LocalSearchKind.note => 'NOTE',
      LocalSearchKind.murmur => 'MURM',
    };
    final visibility = switch (result.visibility) {
      'private' => ContentVisibility.private,
      'unlisted' || 'circle' => ContentVisibility.unlisted,
      _ => ContentVisibility.public,
    };
    return _ResultData(
      kindLabel: kind,
      title: result.title,
      body: result.body,
      when: _formatAge(context, result.updatedAt),
      visibilityColor: _visibilityColor(visibility),
    );
  }

  final String kindLabel;
  final String title;
  final String body;
  final String when;
  final Color visibilityColor;
}

Color _visibilityColor(ContentVisibility visibility) {
  return switch (visibility) {
    ContentVisibility.private => AnsibleDesign.inkMuted,
    ContentVisibility.unlisted => AnsibleDesign.accent,
    ContentVisibility.public => AnsibleDesign.spore,
  };
}

String _formatAge(BuildContext context, DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inHours < 1) {
    final minutes = diff.inMinutes.clamp(0, 59);
    return context.uiCopy(zh: '$minutes分', en: '${minutes}m');
  }
  if (diff.inDays < 1) {
    return context.uiCopy(zh: '${diff.inHours}小時', en: '${diff.inHours}h');
  }
  return context.uiCopy(zh: '${diff.inDays}天', en: '${diff.inDays}d');
}
