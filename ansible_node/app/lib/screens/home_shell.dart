import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../widgets/board_form_dialog.dart';
import '../widgets/thread_form_dialog.dart';
import '../services/network_status_service.dart';
import 'posts_view_screen.dart';
import 'sync_settings_screen.dart';
import 'package:ansible_store/ansible_store.dart' as store;

const _localUserId = 'local-user';
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    this.onLogout,
  });

  final AppDatabase db;
  final VoidCallback? onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final DriftBoardRepository _boardRepo;
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;
  late final DriftUserRepository _userRepo;
  late final DriftReactionRepository _reactionRepo;
  late final NetworkStatusService _networkStatusService;

  List<Board> _boards = [];
  List<PostCardData> _posts = [];
  bool _loading = true;
  String? _selectedBoardId;
  final _uuid = const Uuid();


  @override
  void initState() {
    super.initState();
    _boardRepo = DriftBoardRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _userRepo = DriftUserRepository(widget.db);
    _reactionRepo = DriftReactionRepository(widget.db);
    _networkStatusService = NetworkStatusService();
    _bootstrap().then((_) => _loadData());
  }

  @override
  void dispose() {
    _networkStatusService.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = await _userRepo.getById(_localUserId);
    if (user == null) {
      final now = DateTime.now();
      await _userRepo.create(User(
        userId: _localUserId,
        username: 'local',
        passwordHash: 'local',
        displayName: 'Local User',
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final boards = await _boardRepo.list();
    final threads = await _threadRepo.list(boardId: _selectedBoardId);
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

        final reactions = await _reactionRepo.listByTarget(store.TargetType.thread.name, t.id);
        final countMap = <String, int>{};
        for (final r in reactions) {
          countMap[r.reactionType.name] = (countMap[r.reactionType.name] ?? 0) + 1;
          if (r.userId == _localUserId && r.reactionType == store.ReactionType.thumbsUp) {
            userReacted[t.id] = true;
          }
        }
        reactionCounts[t.id] = countMap;
      }
    }

    // Map boardId -> board for display
    final boardMap = {for (final b in boards) b.id: b};
    threads.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final postCards = threads.map((t) {
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
        reactions: {
          '👍': counts[store.ReactionType.thumbsUp.name] ?? 0,
        },
        comments: comments,
        reacted: userReacted[t.id] ?? false,
      );
    }).toList();

    setState(() {
      _boards = boards;
      _posts = postCards;
      _loading = false;
    });
  }

  void _selectBoard(String? boardId) {
    setState(() {
      _selectedBoardId = boardId;
    });
    _loadData();
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
    await _loadData();
  }

  Future<void> _createThread() async {
    final dialogResult = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => ThreadFormDialog(
        boards: _boards,
        initialBoardId: _selectedBoardId,
      ),
    );
    if (dialogResult == null) return;
    final threadTitle = dialogResult['title']?.trim();
    final boardId = dialogResult['boardId'];
    final content = dialogResult['content']?.trim() ?? '';
    if (threadTitle == null || threadTitle.isEmpty || boardId == null || boardId.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final thread = Thread(
      id: _uuid.v4(),
      boardId: boardId,
      title: threadTitle,
      authorId: _localUserId,
      createdAt: now,
      updatedAt: now,
    );
    await _threadRepo.create(thread);
    // 建立首帖
    final post = Post(
      id: _uuid.v4(),
      threadId: thread.id,
      boardId: boardId,
      authorId: _localUserId,
      content: content,
      createdAt: now,
      updatedAt: now,
      lastEditAt: now,
      parentPostId: null,
    );
    await _postRepo.create(post);
    await _loadData();
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
                            subtitle: board.description != null ? Text(board.description!) : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () async {
                                    final result = await showDialog<Map<String, String?>>(
                                      context: context,
                                      builder: (context) => BoardFormDialog(
                                        initialTitle: board.title,
                                        initialDescription: board.description,
                                      ),
                                    );
                                    if (result != null) {
                                      final now = DateTime.now();
                                      final updatedSlug = _slugify(result['title'] ?? board.title);
                                      final updated = Board(
                                        id: board.id,
                                        slug: updatedSlug.isEmpty ? board.slug : updatedSlug,
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
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('刪除看板'),
                                        content: Text('確定刪除「${board.title}」？此動作不可恢復。'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF050915), Color(0xFF0B1220)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
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
              Expanded(
                child: _MainPanel(
                  db: widget.db,
                  onLogout: widget.onLogout,
                  loading: _loading,
                  posts: _posts,
                  onRefresh: _loadData,
                  onCreateThread: _createThread,
                  onCreateBoard: _createBoard,
                  onManageBoards: _openManageBoards,
                  hasSelectedBoard: _selectedBoardId != null,
                  networkStatusService: _networkStatusService,
                ),
              ),
            ],
          ),
        ),
      ),
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
        color: const Color(0xFF0C1424).withOpacity(0.75),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '訂閱',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add),
                color: const Color(0xFFFF9F43),
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
                      accent: const Color(0xFFFF9F43),
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
                    accent: const Color(0xFFFF9F43),
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
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final baseBg = selected ? const Color(0xFF0F1F34) : const Color(0xFF0F182A);
    final hoverBg = const Color(0xFF122036);
    final borderColor = selected
        ? item.accent.withOpacity(0.35)
        : (_hover ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.05));

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
                    color: item.accent.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: item.accent.withOpacity(0.15),
            foregroundColor: item.accent,
            child: const Text('#', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _hover ? item.accent : Colors.white,
            ),
          ),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )
              : null,
          trailing: item.badge != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D2A3B),
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
    this.accent = const Color(0xFFFF9F43),
  });

  final String title;
  final String? badge;
  final String? subtitle;
  final Color accent;
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    this.onLogout,
    required this.db,
    required this.loading,
    required this.posts,
    required this.onRefresh,
    required this.onCreateThread,
    required this.onCreateBoard,
    required this.onManageBoards,
    required this.hasSelectedBoard,
    required this.networkStatusService,
  });

  final VoidCallback? onLogout;
  final AppDatabase db;
  final bool loading;
  final List<PostCardData> posts;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateThread;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onManageBoards;
  final bool hasSelectedBoard;
  final NetworkStatusService networkStatusService;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TopBar(onLogout: onLogout, onRefresh: onRefresh, db: db, networkStatusService: networkStatusService),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 340,
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('連接錢包以發表文章'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9F43),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton.filled(
                      onPressed: onCreateBoard,
                      icon: const Icon(Icons.add),
                      tooltip: '新增看板',
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: hasSelectedBoard ? onCreateThread : null,
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('建立新討論'),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: onManageBoards,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('管理看板'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : posts.isEmpty
                          ? Center(
                              child: Text(
                                '目前沒有貼文',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white70,
                                    ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: posts.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 16),
                              itemBuilder: (context, index) => PostCard(db: db, data: posts[index]),
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.onLogout, required this.onRefresh, required this.db, required this.networkStatusService});

  final VoidCallback? onLogout;
  final Future<void> Function() onRefresh;
  final AppDatabase db;
  final NetworkStatusService networkStatusService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1424).withOpacity(0.75),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: const Icon(Icons.bolt, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ansible',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ],
          ),
          const Spacer(),
          // Network Status Indicator
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
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('連接錢包'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: const Color(0xFFFF9F43),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            color: Colors.white70,
            tooltip: '重新整理',
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SyncSettingsScreen(db: db),
                ),
              );
            },
            icon: const Icon(Icons.sync),
            color: Colors.white70,
            tooltip: 'Sync Settings',
          ),
          const SizedBox(width: 8),
          if (onLogout != null)
            IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              color: Colors.white70,
              tooltip: '登出',
            ),
        ],
      ),
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
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.view_sidebar_outlined),
          color: Colors.white70,
        ),
        const SizedBox(width: 8),
        const Text(
          '全部文章',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
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
  const PostCard({super.key, required this.data, required this.db});

  final AppDatabase db;
  final PostCardData data;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _hover = false;
  static const _accent = Color(0xFFFF9F43);
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
    if (currentlyReacted) {
      final existing = await _reactionRepo.getByUserAndTarget(
        _localUserId,
        store.TargetType.thread.name,
        targetId,
      );
      if (existing != null) {
        await _reactionRepo.delete(existing.id);
        setState(() {
          _reacted = false;
          _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
        });
      }
    } else {
      final reaction = store.Reaction(
        id: const Uuid().v4(),
        userId: _localUserId,
        targetType: store.TargetType.thread,
        targetId: targetId,
        reactionType: store.ReactionType.thumbsUp,
        createdAt: DateTime.now(),
      );
      await _reactionRepo.create(reaction);
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
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      data.category,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                    color: Colors.white70,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _hover ? _accent : Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.content.isEmpty ? '（尚無內容）' : data.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFBCC7D9),
                  height: 1.5,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(data.author, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 12),
                  const Icon(Icons.forum_outlined, size: 16, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(data.board, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time, size: 16, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(data.timeAgo, style: const TextStyle(color: Colors.white70)),
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
                          builder: (_) => PostsViewScreen(
                            db: widget.db,
                            thread: thread,
                          ),
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
  const _ReactionChip({required this.label, required this.count, this.active = false, this.onTap});

  final String label;
  final int count;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: active ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: active ? const Color(0xFFFF9F43) : Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

