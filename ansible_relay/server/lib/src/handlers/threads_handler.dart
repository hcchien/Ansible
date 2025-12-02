import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/error_response.dart';

class ThreadsHandler {
  ThreadsHandler({
    required ThreadRepository threadRepository,
    required PostRepository postRepository,
  })  : _threadRepository = threadRepository,
        _postRepository = postRepository;

  final ThreadRepository _threadRepository;
  final PostRepository _postRepository;

  Router get router {
    final router = Router();

    router.get('/', _listThreads);
    router.get('/<threadId>', _getThread);
    router.get('/<threadId>/posts', _listPostsForThread);

    return router;
  }

  Future<Response> _listThreads(Request request) async {
    final boardId = request.url.queryParameters['boardId'];
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';

    final threads = await _threadRepository.list(boardId: boardId);
    final visible = includeDeleted ? threads : threads.where((t) => !t.isDeleted).toList();

    return Response.ok(
      jsonEncode({
        'items': visible.map((t) => t.toJson()).toList(),
        'total': visible.length,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _getThread(Request request) async {
    final threadId = request.params['threadId']!;
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';

    final thread = await _threadRepository.getById(threadId);
    if (thread == null || (!includeDeleted && thread.isDeleted)) {
      return ErrorResponse.notFound(
        'THREAD_NOT_FOUND',
        'Thread not found',
      ).toShelfResponse();
    }

    return Response.ok(
      jsonEncode(thread.toJson()),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _listPostsForThread(Request request) async {
    final threadId = request.params['threadId']!;
    final query = request.requestedUri.queryParameters;
    final requestedLimit = int.tryParse(query['limit'] ?? '') ?? 100;
    final limit = requestedLimit.clamp(1, 500).toInt();
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    final includeDeleted = query['includeDeleted'] == 'true';

    final posts = await _postRepository.list(threadId: threadId);
    final filtered = includeDeleted ? posts : posts.where((p) => !p.isDeleted).toList();
    final paginated = filtered.skip(offset).take(limit).toList();

    return Response.ok(
      jsonEncode({
        'items': paginated.map((p) => p.toJson()).toList(),
        'total': filtered.length,
      }),
      headers: _jsonHeaders,
    );
  }
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
