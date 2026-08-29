import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/follow_activity_event.dart' as entity;
import '../../entities/follow_edge.dart' as entity;
import '../../entities/follow_target.dart' as entity;
import '../follow_repository.dart';

class DriftFollowRepository implements FollowRepository {
  final db.AppDatabase _db;

  DriftFollowRepository(this._db);

  @override
  Future<entity.FollowTarget?> getTarget(String targetId) async {
    final row = await (_db.select(
      _db.followTargets,
    )..where((t) => t.targetId.equals(targetId))).getSingleOrNull();
    return row == null ? null : _mapTargetRow(row);
  }

  @override
  Future<entity.FollowTarget?> getTargetByCanonicalUri(
    String canonicalUri,
  ) async {
    final row = await (_db.select(
      _db.followTargets,
    )..where((t) => t.canonicalUri.equals(canonicalUri))).getSingleOrNull();
    return row == null ? null : _mapTargetRow(row);
  }

  @override
  Future<entity.FollowTarget?> getBoardTarget(
    String remoteNodeId,
    String boardId,
  ) async {
    final row =
        await (_db.select(_db.followTargets)..where(
              (t) =>
                  t.remoteNodeId.equals(remoteNodeId) &
                  t.boardId.equals(boardId),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapTargetRow(row);
  }

  @override
  Future<void> upsertTarget(entity.FollowTarget target) async {
    await _db
        .into(_db.followTargets)
        .insert(
          db.FollowTargetsCompanion.insert(
            targetId: target.targetId,
            targetType: target.targetType.name,
            canonicalUri: Value(target.canonicalUri),
            displayName: target.displayName,
            handle: Value(target.handle),
            did: Value(target.did),
            actorUri: Value(target.actorUri),
            inboxUri: Value(target.inboxUri),
            outboxUri: Value(target.outboxUri),
            remoteNodeId: Value(target.remoteNodeId),
            boardId: Value(target.boardId),
            boardSlug: Value(target.boardSlug),
            createdAt: Value(target.createdAt),
            updatedAt: Value(target.updatedAt),
            isDeleted: Value(target.isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.FollowEdge?> getEdge(
    String followerDid,
    String targetId,
    entity.FollowDirection direction,
  ) async {
    final row =
        await (_db.select(_db.followEdges)..where(
              (t) =>
                  t.followerDid.equals(followerDid) &
                  t.targetId.equals(targetId) &
                  t.direction.equals(direction.name),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapEdgeRow(row);
  }

  @override
  Future<List<entity.FollowEdge>> listFollowing(
    String followerDid, {
    entity.FollowTargetType? targetType,
  }) async {
    final query = _db.select(_db.followEdges)
      ..where(
        (t) =>
            t.followerDid.equals(followerDid) &
            t.direction.equals(entity.FollowDirection.outbound.name) &
            t.status.equals(entity.FollowStatus.accepted.name),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);

    if (targetType != null) {
      query.where((t) => t.targetType.equals(targetType.name));
    }

    final rows = await query.get();
    return rows.map(_mapEdgeRow).toList();
  }

  @override
  Future<List<entity.FollowEdge>> listOutbound(
    String followerDid, {
    entity.FollowTargetType? targetType,
  }) async {
    final query = _db.select(_db.followEdges)
      ..where(
        (t) =>
            t.followerDid.equals(followerDid) &
            t.direction.equals(entity.FollowDirection.outbound.name),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    if (targetType != null) {
      query.where((t) => t.targetType.equals(targetType.name));
    }
    return (await query.get()).map(_mapEdgeRow).toList();
  }

  @override
  Future<List<entity.FollowEdge>> listFollowers(String targetId) async {
    final rows =
        await (_db.select(_db.followEdges)
              ..where(
                (t) =>
                    t.targetId.equals(targetId) &
                    t.direction.equals(entity.FollowDirection.inbound.name) &
                    t.status.equals(entity.FollowStatus.accepted.name),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    return rows.map(_mapEdgeRow).toList();
  }

  @override
  Future<List<entity.FollowEdge>> listInbound(String targetId) async {
    final rows =
        await (_db.select(_db.followEdges)
              ..where(
                (t) =>
                    t.targetId.equals(targetId) &
                    t.direction.equals(entity.FollowDirection.inbound.name),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    return rows.map(_mapEdgeRow).toList();
  }

  @override
  Future<void> upsertEdge(entity.FollowEdge edge) async {
    await _db
        .into(_db.followEdges)
        .insert(
          db.FollowEdgesCompanion.insert(
            followId: edge.followId,
            followerDid: edge.followerDid,
            targetId: edge.targetId,
            targetType: edge.targetType.name,
            direction: edge.direction.name,
            status: edge.status.name,
            visibility: edge.visibility.name,
            remoteActivityId: Value(edge.remoteActivityId),
            lastError: Value(edge.lastError),
            createdAt: Value(edge.createdAt),
            updatedAt: Value(edge.updatedAt),
            acceptedAt: Value(edge.acceptedAt),
            cancelledAt: Value(edge.cancelledAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> updateEdgeStatus(
    String followId,
    entity.FollowStatus status,
    DateTime now, {
    String? lastError,
  }) async {
    await (_db.update(
      _db.followEdges,
    )..where((t) => t.followId.equals(followId))).write(
      db.FollowEdgesCompanion(
        status: Value(status.name),
        updatedAt: Value(now),
        acceptedAt: status == entity.FollowStatus.accepted
            ? Value(now)
            : const Value.absent(),
        cancelledAt: status == entity.FollowStatus.cancelled
            ? Value(now)
            : const Value.absent(),
        lastError: Value(lastError),
      ),
    );
  }

  @override
  Future<void> recordEvent(entity.FollowActivityEvent event) async {
    await _db
        .into(_db.followActivityEvents)
        .insert(
          db.FollowActivityEventsCompanion.insert(
            eventId: event.eventId,
            followId: event.followId,
            eventType: event.eventType.name,
            actorDid: event.actorDid,
            activityId: Value(event.activityId),
            message: Value(event.message),
            createdAt: Value(event.createdAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<entity.FollowActivityEvent>> listEvents(String followId) async {
    final rows =
        await (_db.select(_db.followActivityEvents)
              ..where((t) => t.followId.equals(followId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_mapEventRow).toList();
  }

  entity.FollowTarget _mapTargetRow(db.FollowTarget row) {
    return entity.FollowTarget(
      targetId: row.targetId,
      targetType: entity.FollowTargetType.parse(row.targetType),
      canonicalUri: row.canonicalUri,
      displayName: row.displayName,
      handle: row.handle,
      did: row.did,
      actorUri: row.actorUri,
      inboxUri: row.inboxUri,
      outboxUri: row.outboxUri,
      remoteNodeId: row.remoteNodeId,
      boardId: row.boardId,
      boardSlug: row.boardSlug,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
    );
  }

  entity.FollowEdge _mapEdgeRow(db.FollowEdge row) {
    return entity.FollowEdge(
      followId: row.followId,
      followerDid: row.followerDid,
      targetId: row.targetId,
      targetType: entity.FollowTargetType.parse(row.targetType),
      direction: entity.FollowDirection.parse(row.direction),
      status: entity.FollowStatus.parse(row.status),
      visibility: entity.FollowVisibility.parse(row.visibility),
      remoteActivityId: row.remoteActivityId,
      lastError: row.lastError,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      acceptedAt: row.acceptedAt,
      cancelledAt: row.cancelledAt,
    );
  }

  entity.FollowActivityEvent _mapEventRow(db.FollowActivityEvent row) {
    return entity.FollowActivityEvent(
      eventId: row.eventId,
      followId: row.followId,
      eventType: entity.FollowActivityEventType.parse(row.eventType),
      actorDid: row.actorDid,
      activityId: row.activityId,
      message: row.message,
      createdAt: row.createdAt,
    );
  }
}
