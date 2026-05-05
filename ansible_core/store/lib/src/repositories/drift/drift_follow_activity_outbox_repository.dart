import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/outbound_follow_activity.dart' as entity;
import '../follow_activity_outbox_repository.dart';

class DriftFollowActivityOutboxRepository
    implements FollowActivityOutboxRepository {
  final db.AppDatabase _db;

  DriftFollowActivityOutboxRepository(this._db);

  @override
  Future<void> enqueue(entity.OutboundFollowActivity activity) async {
    await _db
        .into(_db.outboundFollowActivities)
        .insert(
          db.OutboundFollowActivitiesCompanion.insert(
            outboxId: activity.outboxId,
            activityId: activity.activityId,
            activityType: activity.activityType.name,
            targetInboxUri: activity.targetInboxUri,
            payloadJson: activity.payloadJson,
            status: activity.status.name,
            attemptCount: Value(activity.attemptCount),
            lastError: Value(activity.lastError),
            createdAt: Value(activity.createdAt),
            updatedAt: Value(activity.updatedAt),
            deliveredAt: Value(activity.deliveredAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<entity.OutboundFollowActivity>> listQueued({
    int limit = 50,
  }) async {
    final rows =
        await (_db.select(_db.outboundFollowActivities)
              ..where(
                (t) => t.status.equals(
                  entity.OutboundFollowActivityStatus.queued.name,
                ),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(limit))
            .get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<void> markDelivering(String outboxId, DateTime now) async {
    final existing = await (_db.select(
      _db.outboundFollowActivities,
    )..where((t) => t.outboxId.equals(outboxId))).getSingleOrNull();
    if (existing == null) return;

    await (_db.update(
      _db.outboundFollowActivities,
    )..where((t) => t.outboxId.equals(outboxId))).write(
      db.OutboundFollowActivitiesCompanion(
        status: Value(entity.OutboundFollowActivityStatus.delivering.name),
        attemptCount: Value(existing.attemptCount + 1),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> markDelivered(String outboxId, DateTime now) async {
    await (_db.update(
      _db.outboundFollowActivities,
    )..where((t) => t.outboxId.equals(outboxId))).write(
      db.OutboundFollowActivitiesCompanion(
        status: Value(entity.OutboundFollowActivityStatus.delivered.name),
        updatedAt: Value(now),
        deliveredAt: Value(now),
      ),
    );
  }

  @override
  Future<void> markFailed(
    String outboxId,
    String lastError,
    DateTime now,
  ) async {
    await (_db.update(
      _db.outboundFollowActivities,
    )..where((t) => t.outboxId.equals(outboxId))).write(
      db.OutboundFollowActivitiesCompanion(
        status: Value(entity.OutboundFollowActivityStatus.failed.name),
        lastError: Value(lastError),
        updatedAt: Value(now),
      ),
    );
  }

  entity.OutboundFollowActivity _mapRowToEntity(db.OutboundFollowActivity row) {
    return entity.OutboundFollowActivity(
      outboxId: row.outboxId,
      activityId: row.activityId,
      activityType: entity.OutboundFollowActivityType.parse(row.activityType),
      targetInboxUri: row.targetInboxUri,
      payloadJson: row.payloadJson,
      status: entity.OutboundFollowActivityStatus.parse(row.status),
      attemptCount: row.attemptCount,
      lastError: row.lastError,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deliveredAt: row.deliveredAt,
    );
  }
}
