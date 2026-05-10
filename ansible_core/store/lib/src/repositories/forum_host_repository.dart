import '../entities/forum_host.dart';

abstract class ForumHostRepository {
  Future<ForumHost?> getById(String forumHostId);
  Future<List<ForumHost>> list({bool includeInactive = true});
  Future<List<ForumHost>> listActive();
  Future<void> upsert(ForumHost host);
}
