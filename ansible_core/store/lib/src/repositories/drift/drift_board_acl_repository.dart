import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/board_acl.dart' as entity;
import '../board_acl_repository.dart';

class DriftBoardAclRepository implements BoardAclRepository {
  final AppDatabase _db;

  DriftBoardAclRepository(this._db);

  @override
  Future<void> setAcl(entity.BoardAcl acl) async {
    await _db.into(_db.boardAcl).insert(
          BoardAclCompanion.insert(
            boardId: acl.boardId,
            userId: acl.userId,
            canRead: Value(acl.canRead),
            canWrite: Value(acl.canWrite),
            isAdmin: Value(acl.isAdmin),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.BoardAcl?> getAcl(String boardId, String userId) async {
    final row = await (_db.select(_db.boardAcl)
          ..where((t) => t.boardId.equals(boardId) & t.userId.equals(userId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.BoardAcl>> getByBoardId(String boardId) async {
    final rows = await (_db.select(_db.boardAcl)..where((t) => t.boardId.equals(boardId))).get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<List<entity.BoardAcl>> getByUserId(String userId) async {
    final rows = await (_db.select(_db.boardAcl)..where((t) => t.userId.equals(userId))).get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<void> deleteAcl(String boardId, String userId) async {
    await (_db.delete(_db.boardAcl)
          ..where((t) => t.boardId.equals(boardId) & t.userId.equals(userId)))
        .go();
  }

  entity.BoardAcl _mapRowToEntity(BoardAclData row) {
    return entity.BoardAcl(
      boardId: row.boardId,
      userId: row.userId,
      canRead: row.canRead,
      canWrite: row.canWrite,
      isAdmin: row.isAdmin,
    );
  }
}
