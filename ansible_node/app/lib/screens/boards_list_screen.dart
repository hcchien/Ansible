import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';
import '../widgets/board_form_dialog.dart';
import 'threads_list_screen.dart';

class BoardsListScreen extends StatefulWidget {
  final AppDatabase db;

  const BoardsListScreen({super.key, required this.db});

  @override
  State<BoardsListScreen> createState() => _BoardsListScreenState();
}

class _BoardsListScreenState extends State<BoardsListScreen> {
  late final DriftBoardRepository _boardRepo;
  List<Board> _boards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _boardRepo = DriftBoardRepository(widget.db);
    _loadBoards();
  }

  Future<void> _loadBoards() async {
    print('Loading boards...');
    setState(() => _isLoading = true);
    final boards = await _boardRepo.list();
    print('Loaded ${boards.length} boards: ${boards.map((b) => b.title).toList()}');
    setState(() {
      _boards = boards;
      _isLoading = false;
    });
  }

  Future<void> _createBoard() async {
    try {
      print('Opening create board dialog...');
      final result = await showDialog<Map<String, String?>>(
        context: context,
        builder: (context) => const BoardFormDialog(),
      );

      print('Dialog result: $result');
      if (result != null) {
        final boardId = const Uuid().v4();
        final now = DateTime.now();
        final slug = _slugify(result['title']!);
        final board = Board(
          id: boardId,
          slug: slug.isEmpty ? boardId : slug,
          title: result['title']!,
          description: result['description'],
          createdAt: now,
          updatedAt: now,
        );
        print('Creating board: ${board.title}');
        await _boardRepo.create(board);
        print('Board created successfully');
        _loadBoards();
      }
    } catch (e, stackTrace) {
      print('Error creating board: $e');
      print('Stack trace: $stackTrace');
    }
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
        title: const Text('Boards'),
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
                        'No boards yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your first board to get started',
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
                        trailing: PopupMenuButton(
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
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
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
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ThreadsListScreen(
                                db: widget.db,
                                board: board,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createBoard,
        tooltip: 'Create Board',
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
