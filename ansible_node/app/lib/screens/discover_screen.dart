import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/discovery_client.dart';
import '../services/elix_content_link.dart';
import '../services/elix_content_router.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/author_label.dart';
import '../widgets/board_gate_badge.dart';
import 'posts_view_screen.dart';
import 'threads_list_screen.dart';
import 'user_profile_screen.dart';

/// The three Discover categories, each shown as a tab so users / boards / posts
/// are always cleanly separated (both while browsing and while searching).
enum _DiscoverTab { people, boards, posts }

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
    this.startOnBoards = false,
  });

  final AppDatabase db;
  final String localDid;
  final DiscoveryClient client;
  final void Function(BoardSearchResult board)? onOpenBoard;

  /// Opens on the 看板 tab (guided first session step 1).
  final bool startOnBoards;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _queryController = TextEditingController();
  Timer? _debounce;

  List<DiscoveredActor> _suggestions = const [];
  List<DiscoveredPost> _explore = const [];
  List<BoardSearchResult> _browseBoards = const [];
  SearchResults _results = const SearchResults();
  bool _loadingFeed = true;
  bool _searching = false;
  String _query = '';
  String? _feedError;
  String? _searchError;
  _DiscoverTab _tab = _DiscoverTab.people;

  @override
  void initState() {
    super.initState();
    if (widget.startOnBoards) _tab = _DiscoverTab.boards;
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
      final suggestions = await widget.client.suggestFollows(
        readerDid: widget.localDid,
        limit: 20,
      );
      final explore = await widget.client.explore(limit: 30);
      // Empty query => browse popular boards for the 看板 tab.
      final boards = await widget.client.searchBoards(query: '', limit: 30);
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _explore = explore;
        _browseBoards = boards;
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

  /// Subscribes to a hosted board (idempotent) and returns the local [Board] so
  /// the caller can navigate into it. Returns null only when there's no forum
  /// host to attach the subscription to.
  Future<Board?> _subscribeToBoard(BoardSearchResult board) async {
    // Capture localized strings before any await (no BuildContext across gaps).
    final addHostMsg = context.uiCopy(
      zh: '請先新增 Forum Host',
      en: 'Add a forum host first',
    );
    final alreadyMsg = context.uiCopy(
      zh: '已訂閱「${board.title}」',
      en: 'Already following "${board.title}"',
    );
    final followingMsg = context.uiCopy(
      zh: '已訂閱「${board.title}」',
      en: 'Following "${board.title}"',
    );

    final hosts = (await DriftRemoteNodeRepository(
      widget.db,
    ).list()).where((n) => n.isActive).toList();
    if (hosts.isEmpty) {
      _toast(addHostMsg);
      return null;
    }
    final host = hosts.first;
    final hostedRepo = DriftHostedBoardRepository(widget.db);
    final subscriptionId = '${host.id}_${board.hostedBoardId}';
    final now = DateTime.now();
    final localBoardId =
        subscriptionId; // also used as slug → guaranteed unique
    final localBoard = Board(
      id: localBoardId,
      slug: localBoardId,
      title: board.title,
      description: board.description,
      createdAt: now,
      updatedAt: now,
    );

    final subs = await hostedRepo.listSubscriptions();
    final alreadySubscribed = subs.any(
      (s) => s.subscriptionId == subscriptionId,
    );

    try {
      await DriftBoardRepository(widget.db).create(localBoard);
    } catch (_) {
      // Board row may already exist from a prior subscribe; continue.
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
        accessPolicy: board.accessPolicy,
        accessPolicyVersion: board.accessPolicyVersion,
        contentVisibility: board.contentVisibility,
        encryptionEpoch: board.encryptionEpoch,
        encryptionState: board.encryptionState,
        federationPolicy: board.federationPolicy,
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
    _toast(alreadySubscribed ? alreadyMsg : followingMsg);
    return localBoard;
  }

  /// Tapping a discovered board subscribes (if needed) and opens it, so the
  /// user lands directly in the board's thread list and can read/post.
  Future<void> _openDiscoveredBoard(BoardSearchResult board) async {
    if (widget.onOpenBoard != null) {
      widget.onOpenBoard!(board);
      return;
    }
    final local = await _subscribeToBoard(board);
    if (local == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadsListScreen(
          db: widget.db,
          board: local,
          localDid: widget.localDid,
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      child: Column(
        children: [
          _searchField(context),
          _tabBar(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: _tabContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          _tabChip(context, _DiscoverTab.people, zh: '使用者', en: 'PEOPLE'),
          _tabChip(context, _DiscoverTab.boards, zh: '看板', en: 'BOARDS'),
          _tabChip(context, _DiscoverTab.posts, zh: '貼文', en: 'POSTS'),
        ],
      ),
    );
  }

  Widget _tabChip(
    BuildContext context,
    _DiscoverTab tab, {
    required String zh,
    required String en,
  }) {
    final active = _tab == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AnsibleDesign.ink : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              context.uiCopy(zh: zh, en: en),
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                letterSpacing: 1.2,
                color: active ? AnsibleDesign.ink : AnsibleDesign.inkFaint,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _tabContent(BuildContext context) {
    final searching = _query.isNotEmpty;
    // Loading / error states (shared across tabs).
    if (searching && _searching) return [_loader()];
    if (searching && _searchError != null) {
      return [_errorPane(context, _searchError!, () => _runSearch(_query))];
    }
    if (!searching && _loadingFeed) return [_loader()];
    if (!searching && _feedError != null) {
      return [_errorPane(context, _feedError!, _loadFeed)];
    }

    switch (_tab) {
      case _DiscoverTab.people:
        // Never surface yourself (or an unopenable empty DID) in a
        // who-to-follow list — tapping those was a silent no-op.
        final actors = (searching ? _results.actors : _suggestions)
            .where((a) => a.did.isNotEmpty && a.did != widget.localDid)
            .toList();
        return actors.isEmpty
            ? [
                _empty(
                  context,
                  searching
                      ? context.uiCopy(zh: '找不到使用者', en: 'No people found')
                      : context.uiCopy(zh: '暫無推薦', en: 'No suggestions yet'),
                ),
              ]
            : [
                AnsibleRuleGroup(
                  children: [for (final a in actors) _actorRow(context, a)],
                ),
              ];
      case _DiscoverTab.boards:
        final boards = searching ? _results.boards : _browseBoards;
        return boards.isEmpty
            ? [
                _empty(
                  context,
                  searching
                      ? context.uiCopy(zh: '找不到看板', en: 'No boards found')
                      : context.uiCopy(zh: '暫無看板', en: 'No boards yet'),
                ),
              ]
            : [
                AnsibleRuleGroup(
                  children: [for (final b in boards) _boardRow(context, b)],
                ),
              ];
      case _DiscoverTab.posts:
        final posts = searching ? _results.posts : _explore;
        return posts.isEmpty
            ? [
                _empty(
                  context,
                  searching
                      ? context.uiCopy(zh: '找不到貼文', en: 'No posts found')
                      : context.uiCopy(zh: '暫無內容', en: 'Nothing here yet'),
                ),
              ]
            : [
                AnsibleRuleGroup(
                  children: [for (final p in posts) _postRow(context, p)],
                ),
              ];
    }
  }

  Widget _loader() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );

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
                        const Icon(
                          Icons.verified,
                          size: 13,
                          color: AnsibleDesign.accent,
                        ),
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
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AnsibleDesign.inkFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardRow(BuildContext context, BoardSearchResult board) {
    return InkWell(
      onTap: () => _openDiscoveredBoard(board),
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
            const Icon(
              Icons.add_circle_outline,
              size: 18,
              color: AnsibleDesign.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _postRow(BuildContext context, DiscoveredPost post) {
    // Thread posts open the thread; personal note/murmur have no thread, so a
    // tap falls back to the author's profile.
    return InkWell(
      onTap: () => _openPost(post),
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
                  post.entityType.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8.5,
                    letterSpacing: 1.4,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: AuthorLabel(
                    did: post.authorDid,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ),
              ],
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

  /// Opens a discovered post. Forum posts route to their thread when it's
  /// available locally; otherwise (or for note/murmur with no thread) falls
  /// back to the author's profile so the tap is never a dead end.
  Future<void> _openPost(DiscoveredPost post) async {
    if (!post.isThreadPost) {
      _openActor(post.authorDid);
      return;
    }
    final resolution = await ElixContentRouter(widget.db).resolve(
      ElixContentRef.thread(boardId: post.boardId!, thread: post.threadId!),
    );
    if (!mounted) return;
    if (resolution is ResolvedThread) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostsViewScreen(
            db: widget.db,
            thread: resolution.thread,
            authorDid: widget.localDid,
          ),
        ),
      );
      return;
    }
    // Thread not synced locally yet — guide the user to the board.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '請先在「看板」分頁訂閱該看板才能閱讀這篇貼文',
            en: 'Follow this board (Boards tab) to read this post',
          ),
        ),
      ),
    );
  }
}
