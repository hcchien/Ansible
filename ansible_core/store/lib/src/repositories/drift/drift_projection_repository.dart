import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/projection.dart' as entity;
import '../projection_repository.dart';

class DriftProjectionRepository implements ProjectionRepository {
  final db.AppDatabase _db;

  DriftProjectionRepository(this._db);

  @override
  Future<void> create(entity.Projection projection) async {
    await _db
        .into(_db.projections)
        .insert(
          db.ProjectionsCompanion.insert(
            projectionId: projection.id,
            sourceContentItemId: projection.sourceContentItemId,
            targetDiscussionId: projection.targetDiscussionId,
            projectedExcerpt: projection.projectedExcerpt,
            participationPolicy: projection.participationPolicy,
            ownershipTransferAcknowledged: Value(
              projection.ownershipTransferAcknowledged,
            ),
            acknowledgedAt: Value(projection.acknowledgedAt),
            createdByDid: projection.createdByDid,
            createdAt: Value(projection.createdAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.Projection?> getById(String id) async {
    final row = await (_db.select(
      _db.projections,
    )..where((table) => table.projectionId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return entity.Projection(
      id: row.projectionId,
      sourceContentItemId: row.sourceContentItemId,
      targetDiscussionId: row.targetDiscussionId,
      projectedExcerpt: row.projectedExcerpt,
      participationPolicy: row.participationPolicy,
      ownershipTransferAcknowledged: row.ownershipTransferAcknowledged,
      acknowledgedAt: row.acknowledgedAt,
      createdByDid: row.createdByDid,
      createdAt: row.createdAt,
    );
  }
}
