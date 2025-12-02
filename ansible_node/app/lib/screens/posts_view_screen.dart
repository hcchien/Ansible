import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';
import '../widgets/post_form_dialog.dart';

class PostsViewScreen extends StatefulWidget {
  final AppDatabase db;
  final Thread thread;

  const PostsViewScreen({
    super.key,
    required this.db,
    required this.thread,
  });

  @override
  State<PostsViewScreen> createState() => _PostsViewScreenState();
}

class _PostsViewScreenState extends State<PostsViewScreen> {
  late final DriftPostRepository _postRepo;
  List<Post> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _postRepo = DriftPostRepository(widget.db);
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    final posts = await _postRepo.list(threadId: widget.thread.id);
    setState(() {
      _posts = posts;
      _isLoading = false;
    });
  }

  Future<void> _createPost() async {
    final content = await showDialog<String>(
      context: context,
      builder: (context) => const PostFormDialog(),
    );

    if (content != null) {
      final now = DateTime.now();
      final post = Post(
        id: const Uuid().v4(),
        threadId: widget.thread.id,
        boardId: widget.thread.boardId,
        authorId: 'user-local', // Placeholder for now
        content: content,
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      );
      await _postRepo.create(post);
      _loadPosts();
    }
  }

  Future<void> _editPost(Post post) async {
    final content = await showDialog<String>(
      context: context,
      builder: (context) => PostFormDialog(initialContent: post.content),
    );

    if (content != null) {
      final now = DateTime.now();
      final updatedPost = Post(
        id: post.id,
        threadId: post.threadId,
        boardId: post.boardId,
        authorId: post.authorId,
        content: content,
        createdAt: post.createdAt,
        updatedAt: now,
        lastEditAt: now,
        parentPostId: post.parentPostId,
        isDeleted: post.isDeleted,
      );
      await _postRepo.update(updatedPost);
      _loadPosts();
    }
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
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
      await _postRepo.delete(post.id);
      _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.thread.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _posts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.message_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No posts yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Be the first to post',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          child: Text(
                                            post.authorId
                                                .substring(0, 1)
                                                .toUpperCase(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                post.authorId,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                              Text(
                                                _formatDate(post.createdAt) +
                                                    (post.lastEditAt
                                                            .isAfter(
                                                                post.createdAt)
                                                        ? ' (edited)'
                                                        : ''),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
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
                                                  Icon(Icons.delete,
                                                      color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Delete',
                                                      style: TextStyle(
                                                          color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _editPost(post);
                                            } else if (value == 'delete') {
                                              _deletePost(post);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(post.content),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    child: ElevatedButton.icon(
                      onPressed: _createPost,
                      icon: const Icon(Icons.add),
                      label: const Text('New Post'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ),
              ],
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
