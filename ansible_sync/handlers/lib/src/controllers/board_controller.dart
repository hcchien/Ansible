import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';
import '../utils/error_responses.dart';
import '../utils/error_code.dart';

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
    try {
      final boards = await _repo.list();
      return Response.ok(
        jsonEncode({'items': boards.map((b) => b.toJson()).toList()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return ErrorResponses.internalError(message: 'Failed to list boards: $e');
    }
  }

  Future<Response> _createBoard(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final board = Board.fromJson(data);
      await _repo.create(board);
      return Response.ok(
        jsonEncode(board.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return ErrorResponses.internalError(message: 'Failed to create board: $e');
    }
  }

  Future<Response> _getBoard(Request request, String id) async {
    try {
      final board = await _repo.getById(id);
      if (board == null) {
        return ErrorResponses.notFound(
          code: ErrorCode.boardNotFound,
          message: 'Board not found',
          details: {'boardId': id},
        );
      }
      return Response.ok(
        jsonEncode(board.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return ErrorResponses.internalError(message: 'Failed to get board: $e');
    }
  }
}
