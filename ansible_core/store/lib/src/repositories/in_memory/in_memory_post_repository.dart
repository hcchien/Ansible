import '../../entities/post.dart';
import '../post_repository.dart';

class InMemoryPostRepository implements PostRepository {
  final Map<String, Post> _posts = {};

  @override
  Future<void> create(Post post) async {
    _posts[post.id] = post;
  }

  @override
  Future<Post?> getById(String id) async {
    return _posts[id];
  }

  @override
  Future<List<Post>> list({String? threadId}) async {
    if (threadId != null) {
      return _posts.values.where((p) => p.threadId == threadId).toList();
    }
    return _posts.values.toList();
  }

  @override
  Future<void> update(Post post) async {
    if (_posts.containsKey(post.id)) {
      _posts[post.id] = post;
    }
  }

  @override
  Future<void> delete(String id) async {
    _posts.remove(id);
  }

  @override
  Future<int> deleteByBoardOlderThan(String boardId, DateTime cutoff) async {
    final idsToDelete = _posts.entries
        .where(
          (entry) =>
              entry.value.boardId == boardId &&
              entry.value.createdAt.isBefore(cutoff),
        )
        .map((entry) => entry.key)
        .toList();
    for (final id in idsToDelete) {
      _posts.remove(id);
    }
    return idsToDelete.length;
  }
}
