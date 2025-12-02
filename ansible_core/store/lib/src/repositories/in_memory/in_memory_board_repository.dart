import '../../entities/board.dart';
import '../board_repository.dart';

class InMemoryBoardRepository implements BoardRepository {
  final Map<String, Board> _boards = {};

  @override
  Future<void> create(Board board) async {
    _boards[board.id] = board;
  }

  @override
  Future<Board?> getById(String id) async {
    return _boards[id];
  }

  @override
  Future<List<Board>> list() async {
    return _boards.values.toList();
  }

  @override
  Future<void> update(Board board) async {
    if (_boards.containsKey(board.id)) {
      _boards[board.id] = board;
    }
  }

  @override
  Future<void> delete(String id) async {
    _boards.remove(id);
  }
}
