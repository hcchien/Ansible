import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';
import '../widgets/thread_form_dialog.dart';
import 'posts_view_screen.dart';

class ThreadsListScreen extends StatefulWidget {
  final AppDatabase db;
  final Board board;

  const ThreadsListScreen({
    super.key,
    required this.db,
    required this.board,
  });

  @override
  State<ThreadsListScreen> createState() => _ThreadsListScreenState();
}

class _ThreadsListScreenState extends State<ThreadsListScreen> {
  late final DriftThreadRepository _threadRepo;
  List<Thread> _threads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _threadRepo = DriftThreadRepository(widget.db);
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() => _isLoading = true);
    final threads = await _threadRepo.list(boardId: widget.board.id);
    setState(() {
      _threads = threads;
      _isLoading = false;
    });
  }

  Future<void> _createThread() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const ThreadFormDialog(),
    );

    if (title != null) {
      final now = DateTime.now();
      final thread = Thread(
        id: const Uuid().v4(),
        boardId: widget.board.id,
        title: title,
        authorId: 'user-local', // Placeholder for now
        createdAt: now,
        updatedAt: now,
      );
      await _threadRepo.create(thread);
      _loadThreads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.board.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _threads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No threads yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a new discussion',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _threads.length,
                  itemBuilder: (context, index) {
                    final thread = _threads[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(thread.title),
                        subtitle: Text(
                          'Created ${_formatDate(thread.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PostsViewScreen(
                                db: widget.db,
                                thread: thread,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createThread,
        tooltip: 'Create Thread',
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}
