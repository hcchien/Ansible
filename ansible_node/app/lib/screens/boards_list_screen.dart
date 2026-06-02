import 'package:ansible_domain/ansible_domain.dart';
import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import '../l10n/app_l10n.dart';
import '../widgets/board_form_dialog.dart';
import '../widgets/follow_button.dart';
import 'threads_list_screen.dart';

class BoardsListScreen extends StatefulWidget {
  final AppDatabase db;

  const BoardsListScreen({super.key, required this.db});

  @override
  State<BoardsListScreen> createState() => _BoardsListScreenState();
}

class _BoardsListScreenState extends State<BoardsListScreen> {
  static const _localFollowerDid = 'did:key:local';

  late final DriftBoardRepository _boardRepo;
  late final DriftFollowRepository _followRepo;
  late final FollowService _followService;
  List<Board> _boards = [];
  Set<String> _followedBoardIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _boardRepo = DriftBoardRepository(widget.db);
    _followRepo = DriftFollowRepository(widget.db);
    _followService = FollowService(
      followRepository: _followRepo,
      outboxRepository: DriftFollowActivityOutboxRepository(widget.db),
      boardSyncConfigRepository: DriftBoardSyncConfigRepository(widget.db),
    );
    _loadBoards();
  }

  Future<void> _loadBoards() async {
    setState(() => _isLoading = true);
    final boards = await _boardRepo.list();
    final followedBoardIds = <String>{};
    for (final board in boards) {
      final target = await _followRepo.getTargetByCanonicalUri(
        'local://boards/${board.id}',
      );
      if (target == null) continue;
      final edge = await _followRepo.getEdge(
        _localFollowerDid,
        target.targetId,
        FollowDirection.outbound,
      );
      if (edge?.status == FollowStatus.accepted) {
        followedBoardIds.add(board.id);
      }
    }
    setState(() {
      _boards = boards;
      _followedBoardIds = followedBoardIds;
      _isLoading = false;
    });
  }

  Future<void> _followBoard(Board board) async {
    await _followService.followBoard(
      followerDid: _localFollowerDid,
      boardId: board.id,
      boardSlug: board.slug,
      displayName: board.title,
      now: DateTime.now().toUtc(),
    );
    await _loadBoards();
  }

  Future<void> _createBoard() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '請從主畫面新增 Elix Relay 託管看板；不再建立本機限定看板。',
            en: 'Add Elix Relay hosted boards from the home screen. Local-only boards are no longer created.',
          ),
        ),
      ),
    );
  }

  Future<void> _editBoard(Board board) async {
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
      final updatedBoard = Board(
        id: board.id,
        slug: updatedSlug.isEmpty ? board.slug : updatedSlug,
        title: result['title'] ?? board.title,
        description: result['description'],
        createdAt: board.createdAt,
        updatedAt: now,
        isDeleted: board.isDeleted,
      );
      await _boardRepo.update(updatedBoard);
      _loadBoards();
    }
  }

  Future<void> _deleteBoard(Board board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Board'),
        content: Text('Are you sure you want to delete "${board.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _boardRepo.delete(board.id);
      _loadBoards();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.uiCopy(zh: '託管看板', en: 'Hosted boards')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _boards.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dashboard_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.uiCopy(zh: '還沒有託管看板', en: 'No hosted boards yet'),
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.uiCopy(
                      zh: '請先新增 Elix Relay，再建立討論看板',
                      en: 'Add an Elix Relay before creating discussion boards',
                    ),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _boards.length,
              itemBuilder: (context, index) {
                final board = _boards[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.dashboard),
                    title: Text(board.title),
                    subtitle: board.description != null
                        ? Text(board.description!)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FollowButton(
                          status: _followedBoardIds.contains(board.id)
                              ? FollowButtonStatus.following
                              : FollowButtonStatus.notFollowing,
                          onPressed: _followedBoardIds.contains(board.id)
                              ? null
                              : () => _followBoard(board),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editBoard(board);
                            } else if (value == 'delete') {
                              _deleteBoard(board);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ThreadsListScreen(db: widget.db, board: board),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createBoard,
        tooltip: context.uiCopy(zh: '建立託管看板', en: 'Create hosted board'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

String _slugify(String input) {
  final slug = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug;
}
