import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/board_publication_target.dart' as publication;
import '../../entities/board_subscription.dart' as subscription_entity;
import '../../entities/hosted_board_projection.dart' as projection_entity;
import '../hosted_board_repository.dart';

class DriftHostedBoardRepository implements HostedBoardRepository {
  DriftHostedBoardRepository(this._db);

  final db.AppDatabase _db;

  @override
  Future<projection_entity.HostedBoardProjection?> getProjection(
    String forumHostId,
    String hostedBoardId,
  ) async {
    final row =
        await (_db.select(_db.hostedBoardProjections)..where(
              (table) =>
                  table.forumHostId.equals(forumHostId) &
                  table.hostedBoardId.equals(hostedBoardId),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapProjection(row);
  }

  @override
  Future<projection_entity.HostedBoardProjection?> getProjectionByLocalBoardId(
    String localBoardId,
  ) async {
    final row =
        await (_db.select(_db.hostedBoardProjections)
              ..where((table) => table.localBoardId.equals(localBoardId)))
            .getSingleOrNull();
    return row == null ? null : _mapProjection(row);
  }

  @override
  Future<List<projection_entity.HostedBoardProjection>> listProjections({
    String? forumHostId,
  }) async {
    final query = _db.select(_db.hostedBoardProjections)
      ..orderBy([(table) => OrderingTerm.asc(table.localSlug)]);
    if (forumHostId != null) {
      query.where((table) => table.forumHostId.equals(forumHostId));
    }
    final rows = await query.get();
    return rows.map(_mapProjection).toList();
  }

  @override
  Future<void> upsertProjection(
    projection_entity.HostedBoardProjection projection,
  ) async {
    final slugOwner =
        await (_db.select(_db.hostedBoardProjections)
              ..where((table) => table.localSlug.equals(projection.localSlug)))
            .getSingleOrNull();
    if (slugOwner != null &&
        slugOwner.localBoardId != projection.localBoardId) {
      throw StateError(
        'Hosted board localSlug "${projection.localSlug}" already belongs to ${slugOwner.localBoardId}',
      );
    }
    await _db
        .into(_db.hostedBoardProjections)
        .insertOnConflictUpdate(
          db.HostedBoardProjectionsCompanion.insert(
            localBoardId: projection.localBoardId,
            forumHostId: projection.forumHostId,
            hostedBoardId: projection.hostedBoardId,
            canonicalBoardUri: projection.canonicalBoardUri,
            remoteSlug: projection.remoteSlug,
            localSlug: projection.localSlug,
            title: projection.title,
            description: Value(projection.description),
            permissionsJson: Value(jsonEncode(projection.permissions)),
            lastSeenCursor: Value(projection.lastSeenCursor),
            createdAt: Value(projection.createdAt),
            updatedAt: Value(projection.updatedAt),
            isDeleted: Value(projection.isDeleted),
          ),
        );
  }

  @override
  Future<List<subscription_entity.BoardSubscription>> listSubscriptions({
    String? forumHostId,
  }) async {
    final query = _db.select(_db.boardSubscriptions)
      ..orderBy([(table) => OrderingTerm.asc(table.subscriptionId)]);
    if (forumHostId != null) {
      query.where((table) => table.forumHostId.equals(forumHostId));
    }
    final rows = await query.get();
    return rows.map(_mapSubscription).toList();
  }

  @override
  Future<void> updateSubscriptionCursor(
    String subscriptionId,
    int cursor,
    DateTime updatedAt,
  ) async {
    await (_db.update(
      _db.boardSubscriptions,
    )..where((table) => table.subscriptionId.equals(subscriptionId))).write(
      db.BoardSubscriptionsCompanion(
        syncCursor: Value(cursor),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  @override
  Future<void> upsertSubscription(
    subscription_entity.BoardSubscription subscription,
  ) async {
    await _db
        .into(_db.boardSubscriptions)
        .insertOnConflictUpdate(
          db.BoardSubscriptionsCompanion.insert(
            subscriptionId: subscription.subscriptionId,
            forumHostId: subscription.forumHostId,
            hostedBoardId: subscription.hostedBoardId,
            localBoardId: subscription.localBoardId,
            readEnabled: Value(subscription.readEnabled),
            writeEnabled: Value(subscription.writeEnabled),
            syncCursor: Value(subscription.syncCursor),
            retentionDays: Value(subscription.retentionDays),
            createdAt: Value(subscription.createdAt),
            updatedAt: Value(subscription.updatedAt),
          ),
        );
  }

  @override
  Future<List<publication.BoardPublicationTarget>> listPublicationTargets({
    publication.BoardPublicationStatus? status,
    String? forumHostId,
  }) async {
    final query = _db.select(_db.boardPublicationTargets)
      ..orderBy([(table) => OrderingTerm.asc(table.targetId)]);
    if (status != null) {
      query.where((table) => table.status.equals(status.name));
    }
    if (forumHostId != null) {
      query.where((table) => table.forumHostId.equals(forumHostId));
    }
    final rows = await query.get();
    return rows.map(_mapPublicationTarget).toList();
  }

  @override
  Future<void> upsertPublicationTarget(
    publication.BoardPublicationTarget target,
  ) async {
    await _db
        .into(_db.boardPublicationTargets)
        .insertOnConflictUpdate(
          db.BoardPublicationTargetsCompanion.insert(
            targetId: target.targetId,
            localSourceId: target.localSourceId,
            sourceType: target.sourceType.name,
            forumHostId: target.forumHostId,
            hostedBoardId: target.hostedBoardId,
            mode: target.mode.name,
            status: Value(target.status.name),
            remoteThreadId: Value(target.remoteThreadId),
            remotePostId: Value(target.remotePostId),
            error: Value(target.error),
            createdAt: Value(target.createdAt),
            updatedAt: Value(target.updatedAt),
          ),
        );
  }

  projection_entity.HostedBoardProjection _mapProjection(
    db.HostedBoardProjection row,
  ) {
    return projection_entity.HostedBoardProjection(
      localBoardId: row.localBoardId,
      forumHostId: row.forumHostId,
      hostedBoardId: row.hostedBoardId,
      canonicalBoardUri: row.canonicalBoardUri,
      remoteSlug: row.remoteSlug,
      localSlug: row.localSlug,
      title: row.title,
      description: row.description,
      permissions: _decodeObjectMap(row.permissionsJson),
      lastSeenCursor: row.lastSeenCursor,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
    );
  }

  subscription_entity.BoardSubscription _mapSubscription(
    db.BoardSubscription row,
  ) {
    return subscription_entity.BoardSubscription(
      subscriptionId: row.subscriptionId,
      forumHostId: row.forumHostId,
      hostedBoardId: row.hostedBoardId,
      localBoardId: row.localBoardId,
      readEnabled: row.readEnabled,
      writeEnabled: row.writeEnabled,
      syncCursor: row.syncCursor,
      retentionDays: row.retentionDays,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  publication.BoardPublicationTarget _mapPublicationTarget(
    db.BoardPublicationTarget row,
  ) {
    return publication.BoardPublicationTarget(
      targetId: row.targetId,
      localSourceId: row.localSourceId,
      sourceType: publication.BoardPublicationSourceType.parse(row.sourceType),
      forumHostId: row.forumHostId,
      hostedBoardId: row.hostedBoardId,
      mode: publication.BoardPublicationMode.parse(row.mode),
      status: publication.BoardPublicationStatus.parse(row.status),
      remoteThreadId: row.remoteThreadId,
      remotePostId: row.remotePostId,
      error: row.error,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Map<String, Object?> _decodeObjectMap(String json) {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }
}
