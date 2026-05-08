import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/content_relation.dart' as entity;
import '../content_relation_repository.dart';

class DriftContentRelationRepository implements ContentRelationRepository {
  final db.AppDatabase _db;

  DriftContentRelationRepository(this._db);

  @override
  Future<void> create(entity.ContentRelation relation) async {
    await _db
        .into(_db.contentRelations)
        .insert(
          db.ContentRelationsCompanion.insert(
            relationId: relation.id,
            fromContentItemId: relation.fromContentItemId,
            toContentItemId: relation.toContentItemId,
            relationType: relation.relationType.name,
            createdByDid: relation.createdByDid,
            createdAt: Value(relation.createdAt),
            localOnly: Value(relation.localOnly),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<entity.ContentRelation>> derivedFrom(String contentItemId) async {
    final rows =
        await (_db.select(_db.contentRelations)
              ..where((table) => table.toContentItemId.equals(contentItemId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.createdAt),
                (table) => OrderingTerm.asc(table.relationId),
              ]))
            .get();
    return rows.map(_mapRow).toList();
  }

  @override
  Future<List<entity.ContentRelation>> sourcesFor(String contentItemId) async {
    final rows =
        await (_db.select(_db.contentRelations)
              ..where((table) => table.fromContentItemId.equals(contentItemId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.createdAt),
                (table) => OrderingTerm.asc(table.relationId),
              ]))
            .get();
    return rows.map(_mapRow).toList();
  }

  entity.ContentRelation _mapRow(db.ContentRelation row) {
    return entity.ContentRelation(
      id: row.relationId,
      fromContentItemId: row.fromContentItemId,
      toContentItemId: row.toContentItemId,
      relationType: entity.RelationType.parse(row.relationType),
      createdByDid: row.createdByDid,
      createdAt: row.createdAt,
      localOnly: row.localOnly,
    );
  }
}
