import 'package:drift/drift.dart';

import '../../db/app_database.dart' as db;
import '../../entities/content_item.dart' as entity;
import '../content_item_repository.dart';

class DriftContentItemRepository implements ContentItemRepository {
  final db.AppDatabase _db;

  DriftContentItemRepository(this._db);

  @override
  Future<void> create(entity.ContentItem item) async {
    await _db
        .into(_db.contentItems)
        .insert(
          db.ContentItemsCompanion.insert(
            contentItemId: item.id,
            authorDid: item.authorDid,
            mode: item.mode.name,
            body: item.body,
            status: item.status.name,
            visibility: item.visibility.name,
            subjectId: Value(item.subjectId),
            title: Value(item.title),
            publishedAt: Value(item.publishedAt),
            createdAt: Value(item.createdAt),
            updatedAt: Value(item.updatedAt),
            isDeleted: Value(item.isDeleted),
            localOnly: Value(item.localOnly),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.update(
      _db.contentItems,
    )..where((table) => table.contentItemId.equals(id))).write(
      db.ContentItemsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<entity.ContentItem?> getById(String id) async {
    final row = await (_db.select(
      _db.contentItems,
    )..where((table) => table.contentItemId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row);
  }

  @override
  Future<List<entity.ContentItem>> list({
    entity.ContentMode? mode,
    String? authorDid,
  }) async {
    final query = _db.select(_db.contentItems);
    query.where((table) => table.isDeleted.equals(false));
    if (mode != null) {
      query.where((table) => table.mode.equals(mode.name));
    }
    if (authorDid != null) {
      query.where((table) => table.authorDid.equals(authorDid));
    }
    query.orderBy([
      (table) => OrderingTerm.asc(table.createdAt),
      (table) => OrderingTerm.asc(table.contentItemId),
    ]);
    final rows = await query.get();
    return rows.map(_mapRow).toList();
  }

  @override
  Future<void> update(entity.ContentItem item) async {
    await (_db.update(
      _db.contentItems,
    )..where((table) => table.contentItemId.equals(item.id))).write(
      db.ContentItemsCompanion(
        authorDid: Value(item.authorDid),
        subjectId: Value(item.subjectId),
        mode: Value(item.mode.name),
        title: Value(item.title),
        body: Value(item.body),
        status: Value(item.status.name),
        visibility: Value(item.visibility.name),
        publishedAt: Value(item.publishedAt),
        updatedAt: Value(item.updatedAt),
        isDeleted: Value(item.isDeleted),
        localOnly: Value(item.localOnly),
      ),
    );
  }

  entity.ContentItem _mapRow(db.ContentItem row) {
    return entity.ContentItem(
      id: row.contentItemId,
      authorDid: row.authorDid,
      subjectId: row.subjectId,
      mode: entity.ContentMode.parse(row.mode),
      title: row.title,
      body: row.body,
      status: entity.ContentStatus.parse(row.status),
      visibility: entity.ContentVisibility.parse(row.visibility),
      publishedAt: row.publishedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
      localOnly: row.localOnly,
    );
  }
}
