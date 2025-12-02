import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/activity_log.dart' as entity;
import '../activity_log_repository.dart';

class DriftActivityLogRepository implements ActivityLogRepository {
  final AppDatabase _db;

  DriftActivityLogRepository(this._db);

  @override
  Future<int> create(entity.ActivityLog log) async {
    final id = await _db.into(_db.activityLog).insert(
          ActivityLogCompanion.insert(
            activityId: log.activityId,
            originNodeId: Value(log.originNodeId),
            type: log.type,
            entityType: log.entityType,
            entityId: log.entityId,
            boardId: Value(log.boardId),
            threadId: Value(log.threadId),
            authorId: log.authorId,
            createdAt: log.createdAt,
            payload: log.payload,
            insertedAt: Value(log.insertedAt ?? DateTime.now()),
          ),
        );
    return id;
  }

  @override
  Future<entity.ActivityLog?> getByActivityId(String activityId) async {
    final row = await (_db.select(_db.activityLog)..where((t) => t.activityId.equals(activityId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.ActivityLog>> list({int? afterLogId, int limit = 50}) async {
    final query = _db.select(_db.activityLog);
    if (afterLogId != null) {
      query.where((t) => t.logId.isBiggerThanValue(afterLogId));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.logId)]);
    query.limit(limit);
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  entity.ActivityLog _mapRowToEntity(ActivityLogData row) {
    return entity.ActivityLog(
      logId: row.logId,
      activityId: row.activityId,
      originNodeId: row.originNodeId,
      type: row.type,
      entityType: row.entityType,
      entityId: row.entityId,
      boardId: row.boardId,
      threadId: row.threadId,
      authorId: row.authorId,
      createdAt: row.createdAt,
      payload: row.payload,
      insertedAt: row.insertedAt,
    );
  }
}
