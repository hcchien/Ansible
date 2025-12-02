import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/board.dart' as entity;
import '../board_repository.dart';

class DriftBoardRepository implements BoardRepository {
  final AppDatabase _db;

  DriftBoardRepository(this._db);

  @override
  Future<void> create(entity.Board board) async {
    await _db.into(_db.boards).insert(
          BoardsCompanion.insert(
            boardId: board.id,
            slug: board.slug,
            title: board.title,
            description: Value(board.description),
            createdAt: Value(board.createdAt),
            updatedAt: Value(board.updatedAt),
            isDeleted: Value(board.isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.Board?> getById(String id) async {
    final row = await (_db.select(_db.boards)..where((t) => t.boardId.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<List<entity.Board>> list() async {
    final rows = await _db.select(_db.boards).get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<void> update(entity.Board board) async {
    await (_db.update(_db.boards)..where((t) => t.boardId.equals(board.id))).write(
      BoardsCompanion(
        slug: Value(board.slug),
        title: Value(board.title),
        description: Value(board.description),
        updatedAt: Value(board.updatedAt),
        isDeleted: Value(board.isDeleted),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    // Soft delete
    await (_db.update(_db.boards)..where((t) => t.boardId.equals(id))).write(
      BoardsCompanion(
        isDeleted: Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  entity.Board _mapRowToEntity(Board row) {
    return entity.Board(
      id: row.boardId,
      slug: row.slug,
      title: row.title,
      description: row.description,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isDeleted: row.isDeleted,
    );
  }
}
