import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/discovery_client.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/board_gate_badge.dart';
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
  String? _feedError;
  String? _searchError;

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
    setState(() {
      _loadingFeed = true;
      _feedError = null;
    });
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFeed = false;
        _feedError = userFacingError(context, error);
      });
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
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await widget.client.search(query: q, limit: 20);
      if (!mounted || _query != q) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || _query != q) return;
      setState(() {
        _searching = false;
        _searchError = userFacingError(context, error);
      });
    }
  }

  Future<void> _subscribeToBoard(BoardSearchResult board) async {
    // Capture localized strings before any await (no BuildContext across gaps).
    final addHostMsg =
        context.uiCopy(zh: '請先新增 Forum Host', en: 'Add a forum host first');
    final alreadyMsg = context.uiCopy(
      zh: '已訂閱「${board.title}」',
      en: 'Already following "${board.title}"',
    );
    final followingMsg = context.uiCopy(
      zh: '已訂閱「${board.title}」',
      en: 'Following "${board.title}"',
    );

    final hosts = (await DriftRemoteNodeRepository(widget.db).list())
        .where((n) => n.isActive)
        .toList();
    if (hosts.isEmpty) {
      _toast(addHostMsg);
      return;
    }
    final host = hosts.first;
    final hostedRepo = DriftHostedBoardRepository(widget.db);
    final subscriptionId = '${host.id}_${board.hostedBoardId}';

    final subs = await hostedRepo.listSubscriptions();
    if (subs.any((s) => s.subscriptionId == subscriptionId)) {
      _toast(alreadyMsg);
      return;
    }

    final now = DateTime.now();
    final localBoardId = subscriptionId; // also used as slug → guaranteed unique
    final localBoard = Board(
      id: localBoardId,
      slug: localBoardId,
      title: board.title,
      description: board.description,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await DriftBoardRepository(widget.db).create(localBoard);
    } catch (_) {
      // Board row may already exist from a prior partial subscribe; continue.
    }
    await hostedRepo.upsertProjection(
      HostedBoardProjection(
        localBoardId: localBoard.id,
        forumHostId: host.id,
        hostedBoardId: board.hostedBoardId,
        canonicalBoardUri: board.canonicalBoardUri ?? '',
        remoteSlug: board.slug ?? board.hostedBoardId,
        localSlug: localBoard.slug,
        title: board.title,
        description: board.description,
        permissions: const {'read': true, 'write': true},
        postingPolicy: board.postingPolicy,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await hostedRepo.upsertSubscription(
      BoardSubscription(
        subscriptionId: subscriptionId,
        forumHostId: host.id,
        hostedBoardId: board.hostedBoardId,
        localBoardId: localBoard.id,
        readEnabled: true,
        writeEnabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    _toast(followingMsg);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    if (_feedError != null) {
      return [_errorPane(context, _feedError!, _loadFeed)];
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
    if (_searchError != null) {
      return [_errorPane(context, _searchError!, () => _runSearch(_query))];
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

  Widget _errorPane(
    BuildContext context,
    String message,
    VoidCallback onRetry,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 28, color: AnsibleDesign.inkFaint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(context.uiCopy(zh: '重試', en: 'Retry')),
          ),
        ],
      ),
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
      onTap: () => widget.onOpenBoard != null
          ? widget.onOpenBoard!(board)
          : _subscribeToBoard(board),
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
                          board.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                      ),
                      if (board.minPostTier ==
                          PostingGate.verifiedHumanTier) ...[
                        const SizedBox(width: 6),
                        const BoardGateBadge(),
                      ],
                    ],
                  ),
                  if ((board.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      board.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.add_circle_outline,
                size: 18, color: AnsibleDesign.accent),
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
