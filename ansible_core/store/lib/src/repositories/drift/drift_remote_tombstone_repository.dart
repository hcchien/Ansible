import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/remote_tombstone.dart';
import '../remote_tombstone_repository.dart';

class DriftRemoteTombstoneRepository implements RemoteTombstoneRepository {
  final AppDatabase _db;
  DriftRemoteTombstoneRepository(this._db);

  @override
  Future<void> upsert(RemoteTombstone item) async {
    await _db
        .into(_db.remoteTombstones)
        .insertOnConflictUpdate(
          RemoteTombstonesCompanion.insert(
            sourceNodeId: item.sourceNodeId,
            entityType: item.entityType,
            entityId: item.entityId,
            boardId: Value(item.boardId),
            authorDid: Value(item.authorDid),
            deletedByDid: item.deletedByDid,
            deletedAt: item.deletedAt,
            receivedAt: item.receivedAt,
          ),
        );
  }

  @override
  Future<RemoteTombstone?> get(
    String sourceNodeId,
    String entityType,
    String entityId,
  ) async {
    final row =
        await (_db.select(_db.remoteTombstones)..where(
              (t) =>
                  t.sourceNodeId.equals(sourceNodeId) &
                  t.entityType.equals(entityType) &
                  t.entityId.equals(entityId),
            ))
            .getSingleOrNull();
    return row == null ? null : _entity(row);
  }

  @override
  Future<List<RemoteTombstone>> list({String? sourceNodeId}) async {
    final query = _db.select(_db.remoteTombstones);
    if (sourceNodeId != null)
      query.where((t) => t.sourceNodeId.equals(sourceNodeId));
    return (await query.get()).map(_entity).toList();
  }

  @override
  Future<void> remove(
    String sourceNodeId,
    String entityType,
    String entityId,
  ) async {
    await (_db.delete(_db.remoteTombstones)..where(
          (t) =>
              t.sourceNodeId.equals(sourceNodeId) &
              t.entityType.equals(entityType) &
              t.entityId.equals(entityId),
        ))
        .go();
  }

  RemoteTombstone _entity(RemoteTombstoneRow row) => RemoteTombstone(
    sourceNodeId: row.sourceNodeId,
    entityType: row.entityType,
    entityId: row.entityId,
    boardId: row.boardId,
    authorDid: row.authorDid,
    deletedByDid: row.deletedByDid,
    deletedAt: row.deletedAt,
    receivedAt: row.receivedAt,
  );
}
