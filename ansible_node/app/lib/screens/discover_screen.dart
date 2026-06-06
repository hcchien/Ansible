import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/discovery_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'user_profile_screen.dart';

/// Network discovery: find people and boards to follow, and explore public
/// content — the antidote to the local-first "island" problem. People + posts
/// come from the AppView; boards come from the relay.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.db,
    required this.localDid,
    required this.client,
    this.onOpenBoard,
  });

  final AppDatabase db;
  final String localDid;
  final DiscoveryClient client;
  final void Function(BoardSearchResult board)? onOpenBoard;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _queryController = TextEditingController();
  Timer? _debounce;

  List<DiscoveredActor> _suggestions = const [];
  List<DiscoveredPost> _explore = const [];
  SearchResults _results = const SearchResults();
  bool _loadingFeed = true;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    setState(() => _loadingFeed = true);
    try {
      final suggestions = await widget.client
          .suggestFollows(readerDid: widget.localDid, limit: 20);
      final explore = await widget.client.explore(limit: 30);
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _explore = explore;
        _loadingFeed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFeed = false);
    }
  }

  void _onQueryChanged(String value) {
    final q = value.trim();
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() => _results = const SearchResults());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    try {
      final results = await widget.client.search(query: q, limit: 20);
      if (!mounted || _query != q) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  void _openActor(String did) {
    if (did.isEmpty || did == widget.localDid) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          db: widget.db,
          followerDid: widget.localDid,
          did: did,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '探索', en: 'DISCOVER'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: ListView(
        children: [
          _searchField(context),
          if (_query.isNotEmpty)
            ..._searchSections(context)
          else
            ..._feedSections(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: TextField(
        controller: _queryController,
        onChanged: _onQueryChanged,
        style: const TextStyle(fontSize: 14, color: AnsibleDesign.ink),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: context.uiCopy(zh: '清除', en: 'Clear'),
                  onPressed: () {
                    _queryController.clear();
                    _onQueryChanged('');
                  },
                  icon: const Icon(Icons.close, size: 16),
                ),
          hintText: context.uiCopy(
            zh: '搜尋使用者、看板、貼文',
            en: 'Search people, boards, posts',
          ),
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
    );
  }

  List<Widget> _feedSections(BuildContext context) {
    if (_loadingFeed) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    return [
      _section(
        context,
        context.uiCopy(zh: '推薦追蹤', en: 'WHO TO FOLLOW'),
        _suggestions.isEmpty
            ? [_empty(context, context.uiCopy(zh: '暫無推薦', en: 'No suggestions yet'))]
            : [for (final a in _suggestions) _actorRow(context, a)],
      ),
      _section(
        context,
        context.uiCopy(zh: '探索', en: 'EXPLORE'),
        _explore.isEmpty
            ? [_empty(context, context.uiCopy(zh: '暫無內容', en: 'Nothing here yet'))]
            : [for (final p in _explore) _postRow(context, p)],
      ),
    ];
  }

  List<Widget> _searchSections(BuildContext context) {
    if (_searching) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    return [
      _section(
        context,
        context.uiCopy(zh: '使用者', en: 'PEOPLE'),
        _results.actors.isEmpty
            ? [_empty(context, context.uiCopy(zh: '找不到使用者', en: 'No people found'))]
            : [for (final a in _results.actors) _actorRow(context, a)],
      ),
      _section(
        context,
        context.uiCopy(zh: '看板', en: 'BOARDS'),
        _results.boards.isEmpty
            ? [_empty(context, context.uiCopy(zh: '找不到看板', en: 'No boards found'))]
            : [for (final b in _results.boards) _boardRow(context, b)],
      ),
      _section(
        context,
        context.uiCopy(zh: '貼文', en: 'POSTS'),
        _results.posts.isEmpty
            ? [_empty(context, context.uiCopy(zh: '找不到貼文', en: 'No posts found'))]
            : [for (final p in _results.posts) _postRow(context, p)],
      ),
    ];
  }

  Widget _section(BuildContext context, String label, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(label, padding: const EdgeInsets.fromLTRB(22, 20, 22, 8)),
        AnsibleRuleGroup(children: rows),
      ],
    );
  }

  Widget _empty(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AnsibleDesign.inkMuted),
        ),
      );

  Widget _actorRow(BuildContext context, DiscoveredActor actor) {
    final subtitle = [
      if (actor.handle != null && actor.handle!.isNotEmpty) '@${actor.handle}',
      if (actor.reason == 'followed_by_people_you_follow')
        context.uiCopy(zh: '你追蹤的人也追蹤', en: 'Followed by people you follow'),
      if (actor.followerCount != null && actor.followerCount! > 0)
        context.uiCopy(
          zh: '${actor.followerCount} 位追蹤者',
          en: '${actor.followerCount} followers',
        ),
    ].join(' · ');

    return InkWell(
      onTap: () => _openActor(actor.did),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          actor.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                      ),
                      if (actor.reputationTier == 'verified_human') ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified,
                            size: 13, color: AnsibleDesign.accent),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AnsibleDesign.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _boardRow(BuildContext context, BoardSearchResult board) {
    return InkWell(
      onTap: widget.onOpenBoard == null ? null : () => widget.onOpenBoard!(board),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              board.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AnsibleDesign.ink,
              ),
            ),
            if ((board.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                board.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AnsibleDesign.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _postRow(BuildContext context, DiscoveredPost post) {
    return InkWell(
      onTap: () => _openActor(post.authorDid),
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
            Text(
              post.entityType.toUpperCase(),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 8.5,
                letterSpacing: 1.4,
                color: AnsibleDesign.inkFaint,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              post.body,
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
}
