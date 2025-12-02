import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/activity.dart';
import '../models/error_response.dart';

class InboxHandler {
  InboxHandler({
    required ActivityLogRepository activityLogRepository,
    required BoardRepository boardRepository,
    required ThreadRepository threadRepository,
    required PostRepository postRepository,
    required BoardAclRepository boardAclRepository,
  })  : _activityLogRepository = activityLogRepository,
        _boardRepository = boardRepository,
        _threadRepository = threadRepository,
        _postRepository = postRepository,
        _boardAclRepository = boardAclRepository;

  final ActivityLogRepository _activityLogRepository;
  final BoardRepository _boardRepository;
  final ThreadRepository _threadRepository;
  final PostRepository _postRepository;
  final BoardAclRepository _boardAclRepository;

  Router get router {
    final router = Router();

    router.post('/', _handleInbox); // /api/v1/inbox

    return router;
  }

  Future<Response> _handleInbox(Request request) async {
    final bodyString = await request.readAsString();
    if (bodyString.isEmpty) {
      return ErrorResponse.validation('Empty body').toShelfResponse();
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyString) as Map<String, dynamic>;
    } catch (_) {
      return ErrorResponse.validation('Invalid JSON').toShelfResponse();
    }

    final activitiesPayload = body['activities'];
    if (activitiesPayload is! List) {
      return ErrorResponse.validation('"activities" must be an array')
          .toShelfResponse();
    }

    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return ErrorResponse.unauthorized().toShelfResponse();
    }

    final results = <Map<String, dynamic>>[];

    for (final raw in activitiesPayload) {
      if (raw is! Map<String, dynamic>) {
        results.add({
          'activityId': null,
          'status': 'invalid',
          'error': 'Activity must be an object',
        });
        continue;
      }

      final activityId = raw['activityId'] as String?;
      try {
        final activity = Activity.fromJson(raw);

        if (activity.authorId != userId) {
          results.add({
            'activityId': activity.activityId,
            'status': 'rejected',
            'error': 'AUTHOR_MISMATCH',
          });
          continue;
        }

        final existing = await _activityLogRepository.getByActivityId(activity.activityId);
        if (existing != null) {
          results.add({
            'activityId': activity.activityId,
            'status': 'duplicate',
            'logId': existing.logId,
          });
          continue;
        }

        final boardIdForAcl = _resolveBoardId(activity);
        if (boardIdForAcl != null && !await _canWrite(boardIdForAcl, userId)) {
          results.add({
            'activityId': activity.activityId,
            'status': 'forbidden',
            'error': 'BOARD_WRITE_DENIED',
          });
          continue;
        }

        final logId = await _applyActivity(activity);
        results.add({
          'activityId': activity.activityId,
          'status': 'accepted',
          'logId': logId,
        });
      } catch (e) {
        results.add({
          'activityId': activityId,
          'status': 'invalid',
          'error': e.toString(),
        });
      }
    }

    return Response.ok(
      jsonEncode({'results': results}),
      headers: _jsonHeaders,
    );
  }

  Future<int> _applyActivity(Activity activity) async {
    final entityType = activity.entityType.toLowerCase();
    switch (entityType) {
      case 'board':
        final board = _boardFromPayload(activity);
        await _applyBoardMutation(activity.type, board, activity);
        break;
      case 'thread':
        final thread = _threadFromPayload(activity);
        await _applyThreadMutation(activity.type, thread, activity);
        break;
      case 'post':
        final post = _postFromPayload(activity);
        await _applyPostMutation(activity.type, post, activity);
        break;
      default:
        throw UnsupportedError('Unsupported entity type ${activity.entityType}');
    }

    final log = ActivityLog(
      activityId: activity.activityId,
      originNodeId: activity.originNodeId,
      type: activity.type,
      entityType: activity.entityType,
      entityId: activity.entityId,
      boardId: _resolveBoardId(activity),
      threadId: activity.threadId,
      authorId: activity.authorId,
      createdAt: activity.createdAt,
      payload: jsonEncode(activity.payload),
      insertedAt: DateTime.now(),
    );
    return _activityLogRepository.create(log);
  }

  Board _boardFromPayload(Activity activity) {
    final payload = Map<String, dynamic>.from(activity.payload);
    payload['id'] ??= activity.entityId;
    payload['slug'] ??= payload['path'] ?? payload['id'];
    payload['createdAt'] ??= activity.createdAt.toIso8601String();
    payload['updatedAt'] ??= activity.createdAt.toIso8601String();
    return Board.fromJson(payload);
  }

  Thread _threadFromPayload(Activity activity) {
    final payload = Map<String, dynamic>.from(activity.payload);
    payload['id'] ??= activity.entityId;
    payload['boardId'] ??= activity.boardId;
    payload['authorId'] ??= activity.authorId;
    payload['createdAt'] ??= activity.createdAt.toIso8601String();
    payload['updatedAt'] ??= activity.createdAt.toIso8601String();
    return Thread.fromJson(payload);
  }

  Post _postFromPayload(Activity activity) {
    final payload = Map<String, dynamic>.from(activity.payload);
    payload['id'] ??= activity.entityId;
    payload['threadId'] ??= activity.threadId;
    payload['boardId'] ??= _resolveBoardId(activity);
    payload['authorId'] ??= activity.authorId;
    payload['createdAt'] ??= activity.createdAt.toIso8601String();
    payload['updatedAt'] ??= activity.createdAt.toIso8601String();
    payload['lastEditAt'] ??= payload['updatedAt'];
    return Post.fromJson(payload);
  }

  Future<void> _applyBoardMutation(String type, Board board, Activity activity) async {
    switch (type) {
      case 'CreateBoard':
      case 'UpsertBoard':
        await _boardRepository.create(board);
        await _boardAclRepository.setAcl(
          BoardAcl(
            boardId: board.id,
            userId: activity.authorId,
            canRead: true,
            canWrite: true,
            isAdmin: true,
          ),
        );
        break;
      case 'UpdateBoard':
        await _boardRepository.update(board);
        break;
      case 'DeleteBoard':
        await _boardRepository.update(
          Board(
            id: board.id,
            slug: board.slug,
            title: board.title,
            description: board.description,
            createdAt: board.createdAt,
            updatedAt: activity.createdAt,
            isDeleted: true,
          ),
        );
        break;
      default:
        throw UnsupportedError('Unsupported board activity $type');
    }
  }

  Future<void> _applyThreadMutation(String type, Thread thread, Activity activity) async {
    switch (type) {
      case 'CreateThread':
      case 'UpsertThread':
        await _threadRepository.create(thread);
        break;
      case 'UpdateThread':
        await _threadRepository.update(thread);
        break;
      case 'DeleteThread':
        await _threadRepository.update(
          Thread(
            id: thread.id,
            boardId: thread.boardId,
            title: thread.title,
            authorId: thread.authorId,
            createdAt: thread.createdAt,
            updatedAt: activity.createdAt,
            isDeleted: true,
          ),
        );
        break;
      default:
        throw UnsupportedError('Unsupported thread activity $type');
    }
  }

  Future<void> _applyPostMutation(String type, Post post, Activity activity) async {
    switch (type) {
      case 'CreatePost':
      case 'UpsertPost':
        await _postRepository.create(post);
        break;
      case 'UpdatePost':
        await _postRepository.update(post);
        break;
      case 'DeletePost':
        await _postRepository.update(
          Post(
            id: post.id,
            threadId: post.threadId,
            boardId: post.boardId,
            authorId: post.authorId,
            content: post.content,
            createdAt: post.createdAt,
            updatedAt: activity.createdAt,
            lastEditAt: activity.createdAt,
            parentPostId: post.parentPostId,
            isDeleted: true,
          ),
        );
        break;
      default:
        throw UnsupportedError('Unsupported post activity $type');
    }
  }

  Future<bool> _canWrite(String boardId, String userId) async {
    final acl = await _boardAclRepository.getAcl(boardId, userId);
    return acl?.canWrite ?? false;
  }

  String? _resolveBoardId(Activity activity) {
    return activity.boardId ??
        (activity.entityType.toLowerCase() == 'board' ? activity.entityId : null) ??
        (activity.payload['boardId'] as String?);
  }
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
