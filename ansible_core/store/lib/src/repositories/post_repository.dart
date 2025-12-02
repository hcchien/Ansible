import '../entities/post.dart';

abstract class PostRepository {
  Future<Post?> getById(String id);
  Future<List<Post>> list({String? threadId});
  Future<void> create(Post post);
  Future<void> update(Post post);
  Future<void> delete(String id);
}
