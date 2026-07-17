import '../entities/remote_tombstone.dart';

abstract class RemoteTombstoneRepository {
  Future<void> upsert(RemoteTombstone tombstone);
  Future<RemoteTombstone?> get(
    String sourceNodeId,
    String entityType,
    String entityId,
  );
  Future<void> remove(String sourceNodeId, String entityType, String entityId);
  Future<List<RemoteTombstone>> list({String? sourceNodeId});
}
