import '../../entities/remote_tombstone.dart';
import '../remote_tombstone_repository.dart';

class InMemoryRemoteTombstoneRepository implements RemoteTombstoneRepository {
  final Map<String, RemoteTombstone> _items = {};

  String _key(String source, String type, String id) => '$source:$type:$id';

  @override
  Future<void> upsert(RemoteTombstone tombstone) async {
    _items[_key(
          tombstone.sourceNodeId,
          tombstone.entityType,
          tombstone.entityId,
        )] =
        tombstone;
  }

  @override
  Future<RemoteTombstone?> get(
    String sourceNodeId,
    String entityType,
    String entityId,
  ) async => _items[_key(sourceNodeId, entityType, entityId)];

  @override
  Future<List<RemoteTombstone>> list({String? sourceNodeId}) async => _items
      .values
      .where(
        (item) => sourceNodeId == null || item.sourceNodeId == sourceNodeId,
      )
      .toList();

  @override
  Future<void> remove(
    String sourceNodeId,
    String entityType,
    String entityId,
  ) async {
    _items.remove(_key(sourceNodeId, entityType, entityId));
  }
}
