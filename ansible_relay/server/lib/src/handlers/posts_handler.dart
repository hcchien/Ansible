import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/error_response.dart';

class PostsHandler {
  PostsHandler({
    required PostRepository postRepository,
  }) : _postRepository = postRepository;

  final PostRepository _postRepository;

  Router get router {
    final router = Router();

    router.get('/', _listPosts);
    router.get('/<postId>', _getPost);

    return router;
  }

  Future<Response> _listPosts(Request request) async {
    final threadId = request.url.queryParameters['threadId'];
    final boardId = request.url.queryParameters['boardId'];
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';
    final requestedLimit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final limit = requestedLimit.clamp(1, 500).toInt();
    final offset = int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;

    final posts = await _postRepository.list(threadId: threadId);
    final filtered = posts.where((post) {
      if (!includeDeleted && post.isDeleted) {
        return false;
      }
      if (boardId != null && boardId.isNotEmpty && post.boardId != boardId) {
        return false;
      }
      return true;
    }).toList();

    final paginated = filtered.skip(offset).take(limit).toList();

    return Response.ok(
      jsonEncode({
        'items': paginated.map((p) => p.toJson()).toList(),
        'total': filtered.length,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _getPost(Request request) async {
    final postId = request.params['postId']!;
    final includeDeleted = request.url.queryParameters['includeDeleted'] == 'true';

    final post = await _postRepository.getById(postId);
    if (post == null || (!includeDeleted && post.isDeleted)) {
      return ErrorResponse.notFound(
        'POST_NOT_FOUND',
        'Post not found',
      ).toShelfResponse();
    }

    return Response.ok(
      jsonEncode(post.toJson()),
      headers: _jsonHeaders,
    );
  }
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
