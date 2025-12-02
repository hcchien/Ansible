import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';

class BoardController {
  final BoardRepository _repo;

  BoardController(this._repo);

  Router get router {
    final router = Router();

    router.get('/', _listBoards);
    router.post('/', _createBoard);
    router.get('/<id>', _getBoard);

    return router;
  }

  Future<Response> _listBoards(Request request) async {
    final boards = await _repo.list();
    return Response.ok(
      jsonEncode(boards.map((b) => b.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _createBoard(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    final board = Board.fromJson(data);
    await _repo.create(board);
    return Response.ok(
      jsonEncode(board.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getBoard(Request request, String id) async {
    final board = await _repo.getById(id);
    if (board == null) {
      return Response.notFound('Board not found');
    }
    return Response.ok(
      jsonEncode(board.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
