import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/board_sync_config.dart' as entity;
import '../board_sync_config_repository.dart';

class DriftBoardSyncConfigRepository implements BoardSyncConfigRepository {
  final AppDatabase _db;

  DriftBoardSyncConfigRepository(this._db);

  @override
  Future<void> create(entity.BoardSyncConfig config) async {
    await _db.into(_db.boardSyncConfigs).insert(
          BoardSyncConfigsCompanion.insert(
            configId: config.id,
            remoteNodeId: config.remoteNodeId,
            boardId: config.boardId,
            syncEnabled: Value(config.syncEnabled),
            createdAt: Value(config.createdAt),
            updatedAt: Value(config.updatedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.BoardSyncConfig?> getById(String id) async {
    final row = await (_db.select(_db.boardSyncConfigs)
          ..where((t) => t.configId.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<entity.BoardSyncConfig?> getByRemoteAndBoard(
      String remoteNodeId, String boardId) async {
    final row = await (_db.select(_db.boardSyncConfigs)
          ..where((t) =>
              t.remoteNodeId.equals(remoteNodeId) & t.boardId.equals(boardId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.BoardSyncConfig>> listByRemote(String remoteNodeId) async {
    final rows = await (_db.select(_db.boardSyncConfigs)
          ..where((t) => t.remoteNodeId.equals(remoteNodeId)))
        .get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<List<String>> getEnabledBoardIds(String remoteNodeId) async {
    final rows = await (_db.select(_db.boardSyncConfigs)
          ..where((t) =>
              t.remoteNodeId.equals(remoteNodeId) & t.syncEnabled.equals(true)))
        .get();
    return rows.map((r) => r.boardId).toList();
  }

  @override
  Future<void> update(entity.BoardSyncConfig config) async {
    await (_db.update(_db.boardSyncConfigs)
          ..where((t) => t.configId.equals(config.id)))
        .write(
      BoardSyncConfigsCompanion(
        remoteNodeId: Value(config.remoteNodeId),
        boardId: Value(config.boardId),
        syncEnabled: Value(config.syncEnabled),
        updatedAt: Value(config.updatedAt),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.boardSyncConfigs)..where((t) => t.configId.equals(id)))
        .go();
  }

  @override
  Future<void> toggleSync(
      String remoteNodeId, String boardId, bool enabled) async {
    final existing = await getByRemoteAndBoard(remoteNodeId, boardId);
    if (existing != null) {
      await (_db.update(_db.boardSyncConfigs)
            ..where((t) => t.configId.equals(existing.id)))
          .write(
        BoardSyncConfigsCompanion(
          syncEnabled: Value(enabled),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      // Create new config if it doesn't exist
      final now = DateTime.now();
      await create(entity.BoardSyncConfig(
        id: '${remoteNodeId}_$boardId',
        remoteNodeId: remoteNodeId,
        boardId: boardId,
        syncEnabled: enabled,
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  entity.BoardSyncConfig _mapRowToEntity(BoardSyncConfig row) {
    return entity.BoardSyncConfig(
      id: row.configId,
      remoteNodeId: row.remoteNodeId,
      boardId: row.boardId,
      syncEnabled: row.syncEnabled,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
