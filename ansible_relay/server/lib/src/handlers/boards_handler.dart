import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/error_response.dart';

class BoardsHandler {
  BoardsHandler({
    required BoardRepository boardRepository,
    required ThreadRepository threadRepository,
  })  : _boardRepository = boardRepository,
        _threadRepository = threadRepository;

  final BoardRepository _boardRepository;
  final ThreadRepository _threadRepository;

  Router get router {
    final router = Router();

    router.get('/', _listBoards);
    router.get('/<boardId>', _getBoard);
    router.get('/<boardId>/threads', _listThreadsForBoard);

    return router;
  }

  Future<Response> _listBoards(Request request) async {
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';
    final boards = await _boardRepository.list();
    final visible = includeDeleted ? boards : boards.where((b) => !b.isDeleted).toList();

    return Response.ok(
      jsonEncode({
        'items': visible.map((b) => b.toJson()).toList(),
        'total': visible.length,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _getBoard(Request request) async {
    final boardId = request.params['boardId']!;
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';

    final board = await _boardRepository.getById(boardId);
    if (board == null || (!includeDeleted && board.isDeleted)) {
      return ErrorResponse.notFound(
        'BOARD_NOT_FOUND',
        'Board not found',
      ).toShelfResponse();
    }

    return Response.ok(
      jsonEncode(board.toJson()),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _listThreadsForBoard(Request request) async {
    final boardId = request.params['boardId']!;
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final offset = int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;

    final threads = await _threadRepository.list(boardId: boardId);
    final filtered = includeDeleted ? threads : threads.where((t) => !t.isDeleted).toList();
    final paginated = filtered.skip(offset).take(limit).toList();

    return Response.ok(
      jsonEncode({
        'items': paginated.map((t) => t.toJson()).toList(),
        'total': filtered.length,
      }),
      headers: _jsonHeaders,
    );
  }
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
