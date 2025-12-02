import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/thread.dart' as entity;
import '../thread_repository.dart';

class DriftThreadRepository implements ThreadRepository {
  final AppDatabase _db;

  DriftThreadRepository(this._db);

  @override
  Future<void> create(entity.Thread thread) async {
    await _db.into(_db.threads).insert(
          ThreadsCompanion.insert(
            threadId: thread.id,
            boardId: thread.boardId,
            title: thread.title,
            authorId: thread.authorId,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            isDeleted: Value(thread.isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.Thread?> getById(String id) async {
    final row = await (_db.select(_db.threads)..where((t) => t.threadId.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.Thread>> list({String? boardId}) async {
    final query = _db.select(_db.threads);
    if (boardId != null) {
      query.where((t) => t.boardId.equals(boardId));
    }
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<void> update(entity.Thread thread) async {
    await (_db.update(_db.threads)..where((t) => t.threadId.equals(thread.id))).write(
      ThreadsCompanion(
        boardId: Value(thread.boardId),
        title: Value(thread.title),
        authorId: Value(thread.authorId),
        updatedAt: Value(thread.updatedAt),
        isDeleted: Value(thread.isDeleted),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    // Soft delete
    await (_db.update(_db.threads)..where((t) => t.threadId.equals(id))).write(
      ThreadsCompanion(
        isDeleted: Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  entity.Thread _mapRowToEntity(Thread row) {
    return entity.Thread(
      id: row.threadId,
      boardId: row.boardId,
      title: row.title,
      authorId: row.authorId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
    );
  }
}
