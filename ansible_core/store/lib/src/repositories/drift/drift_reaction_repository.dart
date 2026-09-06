import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/reaction.dart' as entity;
import '../reaction_repository.dart';

class DriftReactionRepository implements ReactionRepository {
  final AppDatabase _db;

  DriftReactionRepository(this._db);

  @override
  Future<void> create(entity.Reaction reaction) async {
    final existing = await getByUserAndTarget(
      reaction.userId,
      reaction.targetType.name,
      reaction.targetId,
    );
    // Preserve the canonical local id when a duplicate arrives from a retry or
    // another device. A later delete therefore still addresses the reaction
    // the UI originally created.
    if (existing != null && existing.id != reaction.id) return;
    await _db
        .into(_db.reactions)
        .insert(
          ReactionsCompanion.insert(
            id: reaction.id,
            userId: reaction.userId,
            targetType: reaction.targetType.name,
            targetId: reaction.targetId,
            reactionType: reaction.reactionType.name,
            createdAt: reaction.createdAt,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.reactions)..where((r) => r.id.equals(id))).go();
  }

  @override
  Future<List<entity.Reaction>> listByTarget(
    String targetType,
    String targetId,
  ) async {
    final rows =
        await (_db.select(_db.reactions)..where(
              (r) =>
                  r.targetType.equals(targetType) & r.targetId.equals(targetId),
            ))
            .get();
    return rows.map(_mapRowToEntity).toList();
  }

  Stream<List<entity.Reaction>> watchByTarget(
    String targetType,
    String targetId,
  ) {
    return (_db.select(_db.reactions)..where(
          (r) => r.targetType.equals(targetType) & r.targetId.equals(targetId),
        ))
        .watch()
        .map((rows) => rows.map(_mapRowToEntity).toList());
  }

  @override
  Future<entity.Reaction?> getByUserAndTarget(
    String userId,
    String targetType,
    String targetId,
  ) async {
    final row =
        await ((_db.select(_db.reactions)..where(
                (r) =>
                    r.userId.equals(userId) &
                    r.targetType.equals(targetType) &
                    r.targetId.equals(targetId),
              ))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  entity.Reaction _mapRowToEntity(Reaction row) {
    return entity.Reaction(
      id: row.id,
      userId: row.userId,
      targetType: entity.TargetType.values.firstWhere(
        (e) => e.name == row.targetType,
      ),
      targetId: row.targetId,
      reactionType: entity.ReactionType.values.firstWhere(
        (e) => e.name == row.reactionType,
      ),
      createdAt: row.createdAt,
    );
  }
}
