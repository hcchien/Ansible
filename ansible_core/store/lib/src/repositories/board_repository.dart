import '../entities/board.dart';

abstract class BoardRepository {
  Future<Board?> getById(String id);
  Future<List<Board>> list();
  Future<void> create(Board board);
  Future<void> update(Board board);
  Future<void> delete(String id);
}
