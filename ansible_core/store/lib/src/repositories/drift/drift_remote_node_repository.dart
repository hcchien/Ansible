import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/remote_node.dart' as entity;
import '../remote_node_repository.dart';

class DriftRemoteNodeRepository implements RemoteNodeRepository {
  final AppDatabase _db;

  DriftRemoteNodeRepository(this._db);

  @override
  Future<void> create(entity.RemoteNode node) async {
    await _db.into(_db.remoteNodes).insert(
          RemoteNodesCompanion.insert(
            nodeId: node.id,
            name: node.name,
            url: node.url,
            accessToken: Value(node.accessToken),
            syncCursor: Value(node.syncCursor),
            lastSyncAt: Value(node.lastSyncAt),
            createdAt: Value(node.createdAt),
            updatedAt: Value(node.updatedAt),
            isActive: Value(node.isActive),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.RemoteNode?> getById(String id) async {
    final row = await (_db.select(_db.remoteNodes)
          ..where((t) => t.nodeId.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<entity.RemoteNode?> getActive() async {
    final row = await (_db.select(_db.remoteNodes)
          ..where((t) => t.isActive.equals(true)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.RemoteNode>> list() async {
    final rows = await _db.select(_db.remoteNodes).get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<void> update(entity.RemoteNode node) async {
    await (_db.update(_db.remoteNodes)..where((t) => t.nodeId.equals(node.id)))
        .write(
      RemoteNodesCompanion(
        name: Value(node.name),
        url: Value(node.url),
        accessToken: Value(node.accessToken),
        syncCursor: Value(node.syncCursor),
        lastSyncAt: Value(node.lastSyncAt),
        updatedAt: Value(node.updatedAt),
        isActive: Value(node.isActive),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.remoteNodes)..where((t) => t.nodeId.equals(id))).go();
  }

  @override
  Future<void> updateSyncCursor(String id, int cursor, DateTime syncTime) async {
    await (_db.update(_db.remoteNodes)..where((t) => t.nodeId.equals(id)))
        .write(
      RemoteNodesCompanion(
        syncCursor: Value(cursor),
        lastSyncAt: Value(syncTime),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  entity.RemoteNode _mapRowToEntity(RemoteNode row) {
    return entity.RemoteNode(
      id: row.nodeId,
      name: row.name,
      url: row.url,
      accessToken: row.accessToken,
      syncCursor: row.syncCursor,
      lastSyncAt: row.lastSyncAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isActive: row.isActive,
    );
  }
}
