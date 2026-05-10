import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/local_collection.dart' as entity;
import '../local_collection_repository.dart';

class DriftLocalCollectionRepository implements LocalCollectionRepository {
  DriftLocalCollectionRepository(this._db);

  final db.AppDatabase _db;

  @override
  Future<void> upsert(entity.LocalCollection collection) async {
    await _db
        .into(_db.localCollections)
        .insertOnConflictUpdate(
          db.LocalCollectionsCompanion.insert(
            collectionId: collection.collectionId,
            ownerDid: collection.ownerDid,
            title: collection.title,
            description: Value(collection.description),
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt,
            isDeleted: Value(collection.isDeleted),
          ),
        );
  }

  @override
  Future<entity.LocalCollection?> getById(String collectionId) async {
    final row =
        await (_db.select(_db.localCollections)
              ..where((table) => table.collectionId.equals(collectionId)))
            .getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<List<entity.LocalCollection>> list({String? ownerDid}) async {
    final query = _db.select(_db.localCollections)
      ..orderBy([(table) => OrderingTerm.asc(table.title)]);
    if (ownerDid != null) {
      query.where((table) => table.ownerDid.equals(ownerDid));
    }
    final rows = await query.get();
    return rows.map(_mapRow).toList();
  }

  @override
  Future<void> delete(String collectionId, DateTime updatedAt) async {
    await (_db.update(
      _db.localCollections,
    )..where((table) => table.collectionId.equals(collectionId))).write(
      db.LocalCollectionsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  entity.LocalCollection _mapRow(db.LocalCollection row) {
    return entity.LocalCollection(
      collectionId: row.collectionId,
      ownerDid: row.ownerDid,
      title: row.title,
      description: row.description,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
    );
  }
}
