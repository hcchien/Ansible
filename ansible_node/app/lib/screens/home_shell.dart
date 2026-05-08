import 'dart:async';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../widgets/board_form_dialog.dart';
import '../widgets/thread_form_dialog.dart';
import '../services/atproto_client.dart';
import '../services/ai/ai_provider_config_store.dart';
import '../services/network_status_service.dart';
import '../services/ops_dispatch_service.dart';
import '../widgets/ai_provider_setup_sheet.dart';
import '../widgets/feed_filter_tabs.dart';
import '../widgets/ops_queue_status_badge.dart';
import '../widgets/transformation_review_sheet.dart';
import 'murmur_screen.dart';
import 'note_editor_screen.dart';
import 'note_workspace_screen.dart';
import 'posts_view_screen.dart';
import 'sync_settings_screen.dart';
import 'wallet_screen.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import '../theme/ansible_design.dart';

enum _ContentModeTab { murmur, notes, discussions }

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    required this.did,
    this.onClearIdentity,
  });

  final AppDatabase db;
  final String did;
  final VoidCallback? onClearIdentity;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final DriftBoardRepository _boardRepo;
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;
  late final DriftReactionRepository _reactionRepo;
  late final DriftFollowRepository _followRepo;
  late final DriftOpsQueueRepository _opsQueueRepo;
  late final DriftContentItemRepository _contentItemRepo;
  late final DriftAiProviderConfigRepository _aiProviderConfigRepo;
  late final AiProviderConfigStore _aiProviderConfigStore;
  late final OpsDispatchService _opsDispatchService;
  late final AtProtoClient _atProtoClient;
  late final NetworkStatusService _networkStatusService;

  List<Board> _boards = [];
  List<PostCardData> _posts = [];
  bool _loading = true;
  String? _selectedBoardId;
  FeedFilter _feedFilter = FeedFilter.all;
  _ContentModeTab _selectedMode = _ContentModeTab.discussions;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _boardRepo = DriftBoardRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _reactionRepo = DriftReactionRepository(widget.db);
    _followRepo = DriftFollowRepository(widget.db);
    _opsQueueRepo = DriftOpsQueueRepository(widget.db);
    _contentItemRepo = DriftContentItemRepository(widget.db);
    _aiProviderConfigRepo = DriftAiProviderConfigRepository(widget.db);
    _aiProviderConfigStore = AiProviderConfigStore(
      repository: _aiProviderConfigRepo,
    );
    _opsDispatchService = OpsDispatchService(repository: _opsQueueRepo);
    _atProtoClient = AtProtoClient();
    _networkStatusService = NetworkStatusService();
    _loadData();
  }

  @override
  void dispose() {
    _networkStatusService.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final boards = await _boardRepo.list();
    final boardMap = {for (final b in boards) b.id: b};
    final followingEntries = _feedFilter == FeedFilter.following
        ? await FollowFeedProjector(
            followRepository: _followRepo,
            boardRepository: _boardRepo,
            threadRepository: _threadRepo,
            postRepository: _postRepo,
          ).project(followerDid: widget.did)
        : null;
    final threads = followingEntries == null
        ? await _threadRepo.list(boardId: _selectedBoardId)
        : <Thread>[];
    // preload posts per thread for content preview and counts
    final firstPosts = <String, Post?>{};
    final postCounts = <String, int>{};
    final reactionCounts = <String, Map<String, int>>{};
    final userReacted = <String, bool>{};
    for (final t in threads) {
      if (!firstPosts.containsKey(t.id)) {
        final posts = await _postRepo.list(threadId: t.id);
        firstPosts[t.id] = posts.isNotEmpty ? posts.first : null;
        postCounts[t.id] = posts.length;

        final reactions = await _reactionRepo.listByTarget(
          store.TargetType.thread.name,
          t.id,
        );
        final countMap = <String, int>{};
        for (final r in reactions) {
          countMap[r.reactionType.name] =
              (countMap[r.reactionType.name] ?? 0) + 1;
          if (r.userId == widget.did &&
              r.reactionType == store.ReactionType.thumbsUp) {
            userReacted[t.id] = true;
          }
        }
        reactionCounts[t.id] = countMap;
      }
    }

    threads.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final postCards = followingEntries == null
        ? threads.map((t) {
            final board = boardMap[t.boardId];
            final content = firstPosts[t.id]?.content ?? '';
            final comments = postCounts[t.id] ?? 0;
            final counts = reactionCounts[t.id] ?? const {};
            return PostCardData(
              thread: t,
              category: board?.title ?? '未分類',
              title: t.title,
              author: t.authorId,
              board: board?.title ?? t.boardId,
              timeAgo: _formatTimeAgo(t.createdAt),
              content: content,
              reactions: {'👍': counts[store.ReactionType.thumbsUp.name] ?? 0},
              comments: comments,
              reacted: userReacted[t.id] ?? false,
            );
          }).toList()
        : await _buildFollowingPostCards(followingEntries, boardMap);

    setState(() {
      _boards = boards;
      _posts = postCards;
      _loading = false;
    });
  }

  void _selectBoard(String? boardId) {
    setState(() {
      _selectedBoardId = boardId;
      _feedFilter = boardId == null ? FeedFilter.all : FeedFilter.boards;
    });
    _loadData();
  }

  void _selectFeedFilter(FeedFilter filter) {
    setState(() {
      _feedFilter = filter;
      if (filter == FeedFilter.following || filter == FeedFilter.all) {
        _selectedBoardId = null;
      }
    });
    _loadData();
  }

  void _selectMode(_ContentModeTab mode) {
    setState(() => _selectedMode = mode);
  }

  Future<void> _startAiTransformation() async {
    final providers = await _aiProviderConfigRepo.list();
    if (!mounted) return;
    if (providers.isEmpty) {
      final result = await showModalBottomSheet<AiProviderSetupResult>(
        context: context,
        backgroundColor: AnsibleDesign.paper,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const AiProviderSetupSheet(),
      );
      if (result == null) return;
      await _aiProviderConfigStore.save(
        displayName: result.displayName,
        providerType: result.providerType,
        baseUrl: result.baseUrl,
        modelName: result.modelName,
        apiKey: result.apiKey,
        defaultForTransformations: true,
        defaultForSummaries: true,
      );
      if (!mounted) return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TransformationReviewSheet(
        title: 'Draft note',
        body: 'Review AI output before it becomes local content.',
        sourceLabels: const ['Current workspace'],
        containsPrivateSource: true,
        onAccept: (title, body) async {
          final now = DateTime.now().toUtc();
          await _contentItemRepo.create(
            ContentItem(
              id: _uuid.v4(),
              authorDid: widget.did,
              mode: ContentMode.note,
              title: title,
              body: body,
              status: ContentStatus.active,
              visibility: ContentVisibility.private,
              createdAt: now,
              updatedAt: now,
            ),
          );
        },
      ),
    );
  }

  Future<List<PostCardData>> _buildFollowingPostCards(
    List<FollowFeedEntry> entries,
    Map<String, Board> boardMap,
  ) async {
    final cards = <PostCardData>[];
    for (final entry in entries) {
      final posts = await _postRepo.list(threadId: entry.thread.id);
      final reactions = await _reactionRepo.listByTarget(
        store.TargetType.thread.name,
        entry.thread.id,
      );
      final countMap = <String, int>{};
      var reacted = false;
      for (final reaction in reactions) {
        countMap[reaction.reactionType.name] =
            (countMap[reaction.reactionType.name] ?? 0) + 1;
        if (reaction.userId == widget.did &&
            reaction.reactionType == store.ReactionType.thumbsUp) {
          reacted = true;
        }
      }
      final board = entry.board ?? boardMap[entry.post.boardId];
      cards.add(
        PostCardData(
          thread: entry.thread,
          category: board?.title ?? '未分類',
          title: entry.thread.title,
          author: entry.post.authorId,
          board: board?.title ?? entry.post.boardId,
          timeAgo: _formatTimeAgo(entry.post.createdAt),
          content: entry.post.content,
          reactions: {'👍': countMap[store.ReactionType.thumbsUp.name] ?? 0},
          comments: posts.length,
          reacted: reacted,
        ),
      );
    }
    return cards;
  }

  Future<void> _createBoard() async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => const BoardFormDialog(),
    );
    if (result == null) return;
    final now = DateTime.now();
    final id = _uuid.v4();
    final title = result['title']!;
    final slug = _slugify(title);
    final board = Board(
      id: id,
      slug: slug.isEmpty ? id : slug,
      title: title,
      description: result['description'],
      createdAt: now,
      updatedAt: now,
    );
    await _boardRepo.create(board);
    await _enqueueAndFlush(
      CrdtOpBuilder.createBoard(
        authorDid: widget.did,
        entityId: board.id,
        slug: board.slug,
        title: board.title,
        description: board.description,
      ),
    );
    await _loadData();
  }

  Future<void> _createThread() async {
    final dialogResult = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) =>
          ThreadFormDialog(boards: _boards, initialBoardId: _selectedBoardId),
    );
    if (dialogResult == null) return;
    final threadTitle = dialogResult['title']?.trim();
    final boardId = dialogResult['boardId'];
    final content = dialogResult['content']?.trim() ?? '';
    if (threadTitle == null ||
        threadTitle.isEmpty ||
        boardId == null ||
        boardId.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final thread = Thread(
      id: _uuid.v4(),
      boardId: boardId,
      title: threadTitle,
      authorId: widget.did,
      createdAt: now,
      updatedAt: now,
    );
    await _threadRepo.create(thread);
    await _enqueueAndFlush(
      CrdtOpBuilder.createThread(
        authorDid: widget.did,
        entityId: thread.id,
        boardId: boardId,
        title: thread.title,
      ),
    );
    // 建立首帖
    final post = Post(
      id: _uuid.v4(),
      threadId: thread.id,
      boardId: boardId,
      authorId: widget.did,
      content: content,
      createdAt: now,
      updatedAt: now,
      lastEditAt: now,
      parentPostId: null,
    );
    await _postRepo.create(post);
    await _enqueueAndFlush(
      CrdtOpBuilder.createPost(
        authorDid: widget.did,
        entityId: post.id,
        boardId: boardId,
        threadId: thread.id,
        content: post.content,
      ),
    );
    await _loadData();
  }

  Future<void> _enqueueAndFlush(OpsQueueEntry entry) async {
    await _opsDispatchService.signAndEnqueue(entry);
    unawaited(_opsDispatchService.flushPending());
  }

  Future<void> _openManageBoards() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('管理看板'),
              content: SizedBox(
                width: 400,
                child: _boards.isEmpty
                    ? const Text('目前沒有看板')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _boards.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final board = _boards[index];
                          return ListTile(
                            title: Text(board.title),
                            subtitle: board.description != null
                                ? Text(board.description!)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () async {
                                    final result =
                                        await showDialog<Map<String, String?>>(
                                          context: context,
                                          builder: (context) => BoardFormDialog(
                                            initialTitle: board.title,
                                            initialDescription:
                                                board.description,
                                          ),
                                        );
                                    if (result != null) {
                                      final now = DateTime.now();
                                      final updatedSlug = _slugify(
                                        result['title'] ?? board.title,
                                      );
                                      final updated = Board(
                                        id: board.id,
                                        slug: updatedSlug.isEmpty
                                            ? board.slug
                                            : updatedSlug,
                                        title: result['title'] ?? board.title,
                                        description: result['description'],
                                        createdAt: board.createdAt,
                                        updatedAt: now,
                                        isDeleted: board.isDeleted,
                                      );
                                      await _boardRepo.update(updated);
                                      await _loadData();
                                      setStateDialog(() {});
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('刪除看板'),
                                        content: Text(
                                          '確定刪除「${board.title}」？此動作不可恢復。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            child: const Text('刪除'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await _boardRepo.delete(board.id);
                                      await _loadData();
                                      setStateDialog(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('關閉'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _createBoard();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新增看板'),
                ),
              ],
            );
          },
        );
      },
    );
    await _loadData();
  }

  String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    return '${diff.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          color: AnsibleDesign.paper,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final mainPanel = _MainPanel(
                db: widget.db,
                did: widget.did,
                opsQueueRepo: _opsQueueRepo,
                opsDispatchService: _opsDispatchService,
                atProtoClient: _atProtoClient,
                onClearIdentity: widget.onClearIdentity,
                loading: _loading,
                posts: _posts,
                onRefresh: _loadData,
                onCreateThread: _createThread,
                onCreateBoard: _createBoard,
                onManageBoards: _openManageBoards,
                onOpenBoards: compact ? () => _openBoardsSheet(context) : null,
                feedFilter: _feedFilter,
                onFeedFilterChanged: _selectFeedFilter,
                hasSelectedBoard: _selectedBoardId != null,
                selectedBoardId: _selectedBoardId,
                boards: _boards,
                networkStatusService: _networkStatusService,
                selectedMode: _selectedMode,
                onModeChanged: _selectMode,
                contentItemRepository: _contentItemRepo,
                onStartAiAction: _startAiTransformation,
              );

              if (compact) {
                return mainPanel;
              }

              return Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: _Sidebar(
                      boards: _boards,
                      selectedBoardId: _selectedBoardId,
                      onSelectBoard: _selectBoard,
                      onManageBoards: _loadData,
                    ),
                  ),
                  Expanded(child: mainPanel),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openBoardsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: _Sidebar(
              boards: _boards,
              selectedBoardId: _selectedBoardId,
              onSelectBoard: (boardId) {
                Navigator.of(sheetContext).pop();
                _selectBoard(boardId);
              },
              onManageBoards: () {
                Navigator.of(sheetContext).pop();
                _openManageBoards();
              },
            ),
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.boards,
    required this.selectedBoardId,
    required this.onSelectBoard,
    required this.onManageBoards,
  });

  final List<Board> boards;
  final String? selectedBoardId;
  final ValueChanged<String?> onSelectBoard;
  final VoidCallback onManageBoards;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border(
          right: BorderSide(color: AnsibleDesign.rule.withValues(alpha: 0.8)),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '圈 · CIRCLE',
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add),
                color: AnsibleDesign.accent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: boards.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _BoardTile(
                    item: BoardNavItem(
                      title: '全部動態',
                      badge: '${boards.length} 看板',
                      accent: AnsibleDesign.accent,
                    ),
                    selected: selectedBoardId == null,
                    onTap: () => onSelectBoard(null),
                  );
                }
                final board = boards[index - 1];
                return _BoardTile(
                  item: BoardNavItem(
                    title: board.title,
                    badge: null,
                    subtitle: board.slug,
                    accent: AnsibleDesign.accent,
                  ),
                  selected: selectedBoardId == board.id,
                  onTap: () => onSelectBoard(board.id),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onManageBoards,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('管理訂閱'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AnsibleDesign.ink,
              side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardTile extends StatefulWidget {
  const _BoardTile({required this.item, this.selected = false, this.onTap});

  final BoardNavItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_BoardTile> createState() => _BoardTileState();
}

class _BoardTileState extends State<_BoardTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final item = widget.item;
    final baseBg = selected ? AnsibleDesign.paperDeep : AnsibleDesign.paperElev;
    final hoverBg = AnsibleDesign.paperDeep;
    final borderColor = selected
        ? item.accent.withValues(alpha: 0.35)
        : (_hover ? AnsibleDesign.rule : AnsibleDesign.ruleSoft);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..translate(0.0, _hover ? -2.0 : 0.0),
        decoration: BoxDecoration(
          color: _hover ? hoverBg : baseBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: item.accent.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: item.accent.withValues(alpha: 0.15),
            foregroundColor: item.accent,
            child: const Text(
              '#',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _hover ? item.accent : AnsibleDesign.ink,
            ),
          ),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: const TextStyle(
                    color: AnsibleDesign.inkMuted,
                    fontSize: 12,
                  ),
                )
              : null,
          trailing: item.badge != null
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnsibleDesign.paperDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.badge!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                )
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class BoardNavItem {
  BoardNavItem({
    required this.title,
    this.badge,
    this.subtitle,
    this.accent = AnsibleDesign.accent,
  });

  final String title;
  final String? badge;
  final String? subtitle;
  final Color accent;
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    this.onClearIdentity,
    required this.db,
    required this.did,
    required this.opsQueueRepo,
    required this.opsDispatchService,
    required this.atProtoClient,
    required this.loading,
    required this.posts,
    required this.onRefresh,
    required this.onCreateThread,
    required this.onCreateBoard,
    required this.onManageBoards,
    this.onOpenBoards,
    required this.feedFilter,
    required this.onFeedFilterChanged,
    required this.hasSelectedBoard,
    required this.selectedBoardId,
    required this.boards,
    required this.networkStatusService,
    required this.selectedMode,
    required this.onModeChanged,
    required this.contentItemRepository,
    required this.onStartAiAction,
  });

  final VoidCallback? onClearIdentity;
  final AppDatabase db;
  final String did;
  final OpsQueueRepository opsQueueRepo;
  final OpsDispatchService opsDispatchService;
  final AtProtoClient atProtoClient;
  final bool loading;
  final List<PostCardData> posts;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateThread;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onManageBoards;
  final VoidCallback? onOpenBoards;
  final FeedFilter feedFilter;
  final ValueChanged<FeedFilter> onFeedFilterChanged;
  final bool hasSelectedBoard;
  final String? selectedBoardId;
  final List<Board> boards;
  final NetworkStatusService networkStatusService;
  final _ContentModeTab selectedMode;
  final ValueChanged<_ContentModeTab> onModeChanged;
  final ContentItemRepository contentItemRepository;
  final Future<void> Function() onStartAiAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final contentPadding = compact
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 28, vertical: 12);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              onClearIdentity: onClearIdentity,
              onRefresh: onRefresh,
              db: db,
              did: did,
              opsQueueRepo: opsQueueRepo,
              opsDispatchService: opsDispatchService,
              networkStatusService: networkStatusService,
            ),
            Expanded(
              child: Padding(
                padding: contentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(onOpenBoards: onOpenBoards),
                    const SizedBox(height: 10),
                    _ModeNavigation(
                      selected: selectedMode,
                      onChanged: onModeChanged,
                    ),
                    const SizedBox(height: 12),
                    if (selectedMode == _ContentModeTab.discussions) ...[
                      FeedFilterTabs(
                        selected: feedFilter,
                        onChanged: onFeedFilterChanged,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: compact ? double.infinity : 340,
                          child: FilledButton.icon(
                            onPressed:
                                (hasSelectedBoard && selectedBoardId != null)
                                ? () {
                                    // Use the selected board for a placeholder threadId.
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => NoteEditorScreen(
                                          authorDid: did,
                                          boardId: selectedBoardId!,
                                          threadId: '',
                                          threadTitle:
                                              boards
                                                  .where(
                                                    (b) =>
                                                        b.id == selectedBoardId,
                                                  )
                                                  .map((b) => b.title)
                                                  .firstOrNull ??
                                              '新討論',
                                          atProtoClient: atProtoClient,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            label: const Text('新貼文'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AnsibleDesign.ink,
                              foregroundColor: AnsibleDesign.paper,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message: '新增看板',
                            child: IconButton.filled(
                              onPressed: onCreateBoard,
                              icon: const Icon(Icons.add),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: hasSelectedBoard ? onCreateThread : null,
                            icon: const Icon(Icons.forum_outlined),
                            label: Text(compact ? '新討論' : '建立新討論'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onManageBoards,
                            icon: const Icon(Icons.settings_outlined),
                            label: Text(compact ? '看板' : '管理看板'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onStartAiAction,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('AI 助手'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onStartAiAction,
                            icon: const Icon(Icons.summarize_outlined),
                            label: const Text('AI 摘要'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: switch (selectedMode) {
                        _ContentModeTab.murmur => MurmurScreen(
                          authorDid: did,
                          contentItemRepository: contentItemRepository,
                        ),
                        _ContentModeTab.notes => const NoteWorkspaceScreen(),
                        _ContentModeTab.discussions =>
                          loading
                              ? const Center(child: CircularProgressIndicator())
                              : posts.isEmpty
                              ? Center(
                                  child: Text(
                                    '目前沒有貼文',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: AnsibleDesign.inkMuted,
                                        ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: posts.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 16),
                                  itemBuilder: (context, index) => PostCard(
                                    db: db,
                                    data: posts[index],
                                    authorDid: did,
                                    opsDispatchService: opsDispatchService,
                                  ),
                                ),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    this.onClearIdentity,
    required this.onRefresh,
    required this.db,
    required this.did,
    required this.opsQueueRepo,
    required this.opsDispatchService,
    required this.networkStatusService,
  });

  final VoidCallback? onClearIdentity;
  final Future<void> Function() onRefresh;
  final AppDatabase db;
  final String did;
  final OpsQueueRepository opsQueueRepo;
  final OpsDispatchService opsDispatchService;
  final NetworkStatusService networkStatusService;

  String get _truncatedDid {
    if (did.length <= 24) return did;
    return '${did.substring(0, 18)}...${did.substring(did.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;

          return Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AnsibleMark(size: 30),
                  const SizedBox(width: 10),
                  const Text(
                    'ansible',
                    style: TextStyle(fontWeight: FontWeight.w300, fontSize: 22),
                  ),
                ],
              ),
              const Spacer(),
              if (!compact) ...[
                ListenableBuilder(
                  listenable: networkStatusService,
                  builder: (context, _) {
                    return _NetworkStatusIndicator(
                      status: networkStatusService.status,
                      connectionType: networkStatusService.connectionType,
                      onTap: () => networkStatusService.checkStatus(),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
              compact
                  ? IconButton.filled(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WalletScreen(
                              holderDid: did,
                              repository: DriftWalletRepository(db),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      tooltip: '連接錢包',
                    )
                  : TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WalletScreen(
                              holderDid: did,
                              repository: DriftWalletRepository(db),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                      label: const Text('連接錢包'),
                      style: TextButton.styleFrom(
                        foregroundColor: AnsibleDesign.paper,
                        backgroundColor: AnsibleDesign.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnsibleDesign.paperElev,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fingerprint,
                        size: 16,
                        color: AnsibleDesign.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _truncatedDid,
                        style: const TextStyle(
                          color: AnsibleDesign.inkMuted,
                          fontSize: 12,
                          fontFamily: AnsibleDesign.mono,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OpsQueueStatusBadge(repository: opsQueueRepo),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                onPressed: () async {
                  await opsDispatchService.flushPending();
                  await onRefresh();
                },
                icon: const Icon(Icons.refresh),
                color: AnsibleDesign.inkMuted,
                tooltip: '同步並重新整理',
              ),
              if (!compact)
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SyncSettingsScreen(db: db),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sync),
                  color: AnsibleDesign.inkMuted,
                  tooltip: 'Sync Settings',
                ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: AnsibleDesign.inkMuted,
                ),
                tooltip: '選單',
                onSelected: (value) {
                  if (value == 'clear_identity' && onClearIdentity != null) {
                    onClearIdentity!();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'clear_identity',
                    child: Row(
                      children: [
                        Icon(Icons.no_accounts_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('清除身份 (Clear Identity)'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeNavigation extends StatelessWidget {
  const _ModeNavigation({required this.selected, required this.onChanged});

  final _ContentModeTab selected;
  final ValueChanged<_ContentModeTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_ContentModeTab>(
      style: SegmentedButton.styleFrom(
        backgroundColor: AnsibleDesign.paper,
        selectedBackgroundColor: AnsibleDesign.paperDeep,
        foregroundColor: AnsibleDesign.inkMuted,
        selectedForegroundColor: AnsibleDesign.ink,
        side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
      ),
      segments: const [
        ButtonSegment(
          value: _ContentModeTab.murmur,
          icon: Icon(Icons.chat_bubble_outline),
          label: Text('碎念'),
        ),
        ButtonSegment(
          value: _ContentModeTab.notes,
          icon: Icon(Icons.sticky_note_2_outlined),
          label: Text('筆記'),
        ),
        ButtonSegment(
          value: _ContentModeTab.discussions,
          icon: Icon(Icons.forum_outlined),
          label: Text('討論'),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

class _NetworkStatusIndicator extends StatelessWidget {
  const _NetworkStatusIndicator({
    required this.status,
    required this.connectionType,
    this.onTap,
  });

  final NetworkStatus status;
  final String connectionType;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String tooltip;

    switch (status) {
      case NetworkStatus.online:
        icon = Icons.wifi;
        color = Colors.green;
        tooltip = 'Online ($connectionType)';
        break;
      case NetworkStatus.offline:
        icon = Icons.wifi_off;
        color = Colors.red;
        tooltip = 'Offline';
        break;
      case NetworkStatus.checking:
        icon = Icons.wifi_find;
        color = Colors.orange;
        tooltip = 'Checking connection...';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == NetworkStatus.checking)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                status == NetworkStatus.online
                    ? connectionType
                    : status == NetworkStatus.offline
                    ? 'Offline'
                    : 'Checking',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({this.onOpenBoards});

  final VoidCallback? onOpenBoards;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onOpenBoards,
          icon: const Icon(Icons.view_sidebar_outlined),
          color: AnsibleDesign.inkMuted,
          tooltip: '訂閱',
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '討論串',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w500,
              color: AnsibleDesign.ink,
            ),
          ),
        ),
        const AnsibleStatusChip(label: '公開 · OPEN', dot: AnsibleDesign.accent),
      ],
    );
  }
}

class PostCardData {
  PostCardData({
    required this.thread,
    required this.category,
    required this.title,
    required this.content,
    required this.author,
    required this.board,
    required this.timeAgo,
    required this.reactions,
    required this.comments,
    required this.reacted,
  });

  final Thread thread;
  final String category;
  final String title;
  final String content;
  final String author;
  final String board;
  final String timeAgo;
  final Map<String, int> reactions;
  final int comments;
  final bool reacted;
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.data,
    required this.db,
    required this.authorDid,
    required this.opsDispatchService,
  });

  final AppDatabase db;
  final PostCardData data;
  final String authorDid;
  final OpsDispatchService opsDispatchService;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _hover = false;
  static const _accent = AnsibleDesign.accent;
  late final store.DriftReactionRepository _reactionRepo;
  bool _isReacting = false;
  bool _reacted = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _reacted = widget.data.reacted;
    _likeCount = widget.data.reactions['👍'] ?? 0;
    _reactionRepo = store.DriftReactionRepository(widget.db);
  }

  Future<void> _toggleThumbsUp(String targetId, bool currentlyReacted) async {
    final localDid = widget.authorDid;
    if (currentlyReacted) {
      final existing = await _reactionRepo.getByUserAndTarget(
        localDid,
        store.TargetType.thread.name,
        targetId,
      );
      if (existing != null) {
        await _reactionRepo.delete(existing.id);
        await widget.opsDispatchService.signAndEnqueue(
          CrdtOpBuilder.deleteReaction(
            authorDid: localDid,
            entityId: existing.id,
            targetType: store.TargetType.thread.name,
            targetId: targetId,
          ),
        );
        unawaited(widget.opsDispatchService.flushPending());
        setState(() {
          _reacted = false;
          _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
        });
      }
    } else {
      final reaction = store.Reaction(
        id: const Uuid().v4(),
        userId: localDid,
        targetType: store.TargetType.thread,
        targetId: targetId,
        reactionType: store.ReactionType.thumbsUp,
        createdAt: DateTime.now(),
      );
      await _reactionRepo.create(reaction);
      await widget.opsDispatchService.signAndEnqueue(
        CrdtOpBuilder.createReaction(
          authorDid: localDid,
          entityId: reaction.id,
          targetType: reaction.targetType.name,
          targetId: reaction.targetId,
          reactionType: reaction.reactionType.name,
        ),
      );
      unawaited(widget.opsDispatchService.flushPending());
      setState(() {
        _reacted = true;
        _likeCount += 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final thread = data.thread;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PostsViewScreen(
                db: widget.db,
                thread: thread,
                authorDid: widget.authorDid,
                opsDispatchService: widget.opsDispatchService,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: AnsibleDesign.paperElev,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AnsibleDesign.paperDeep,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      data.category,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                    color: AnsibleDesign.inkMuted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _hover ? _accent : AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.content.isEmpty ? '（尚無內容）' : data.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AnsibleDesign.inkMuted,
                  height: 1.5,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.author,
                    style: const TextStyle(color: AnsibleDesign.inkMuted),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.forum_outlined,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.board,
                    style: const TextStyle(color: AnsibleDesign.inkMuted),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.timeAgo,
                    style: const TextStyle(color: AnsibleDesign.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _ReactionChip(
                      label: '👍',
                      count: _likeCount,
                      active: _reacted,
                      onTap: _isReacting
                          ? null
                          : () async {
                              setState(() => _isReacting = true);
                              try {
                                await _toggleThumbsUp(thread.id, _reacted);
                              } finally {
                                setState(() => _isReacting = false);
                              }
                            },
                    ),
                  ),
                  _CommentChip(
                    count: data.comments,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PostsViewScreen(db: widget.db, thread: thread),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.label,
    required this.count,
    this.active = false,
    this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: active ? AnsibleDesign.paper : AnsibleDesign.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: active ? AnsibleDesign.ink : AnsibleDesign.paperDeep,
        shape: const StadiumBorder(),
      ),
      child: Text('$label $count'),
    );
  }
}

class _CommentChip extends StatelessWidget {
  const _CommentChip({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.chat_bubble_outline, size: 18),
      label: Text('$count 則留言'),
      style: TextButton.styleFrom(
        foregroundColor: AnsibleDesign.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: AnsibleDesign.paperDeep,
        shape: const StadiumBorder(),
      ),
    );
  }
}
