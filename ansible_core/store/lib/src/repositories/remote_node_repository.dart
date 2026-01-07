import '../entities/remote_node.dart';

abstract class RemoteNodeRepository {
  Future<RemoteNode?> getById(String id);
  Future<RemoteNode?> getActive();
  Future<List<RemoteNode>> list();
  Future<void> create(RemoteNode node);
  Future<void> update(RemoteNode node);
  Future<void> delete(String id);
  Future<void> updateSyncCursor(String id, int cursor, DateTime syncTime);
}
