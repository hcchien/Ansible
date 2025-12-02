import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/activity.dart';
import '../models/error_response.dart';

class SyncHandler {
  SyncHandler({
    required ActivityLogRepository activityLogRepository,
  }) : _activityLogRepository = activityLogRepository;

  final ActivityLogRepository _activityLogRepository;

  Router get router {
    final router = Router();

    router.get('/delta', _getDelta);

    return router;
  }

  Future<Response> _getDelta(Request request) async {
    final query = request.requestedUri.queryParameters;
    final cursorStr = query['cursor'];
    final limitStr = query['limit'];

    int? cursor;
    if (cursorStr != null && cursorStr.isNotEmpty) {
      cursor = int.tryParse(cursorStr);
      if (cursor == null || cursor < 0) {
        return ErrorResponse.validation('Invalid cursor').toShelfResponse();
      }
    }

    final requestedLimit = int.tryParse(limitStr ?? '') ?? 100;
    final effectiveLimit = requestedLimit.clamp(1, 500).toInt();

    final entries =
        await _activityLogRepository.list(afterLogId: cursor, limit: effectiveLimit + 1);
    final hasMore = entries.length > effectiveLimit;
    final visible = hasMore ? entries.sublist(0, effectiveLimit) : entries;

    final responseActivities = visible
        .map(
          (log) => ActivityLogEntry(
            logId: log.logId!,
            activity: Activity(
              activityId: log.activityId,
              originNodeId: log.originNodeId,
              type: log.type,
              entityType: log.entityType,
              entityId: log.entityId,
              boardId: log.boardId,
              threadId: log.threadId,
              authorId: log.authorId,
              createdAt: log.createdAt,
              payload: jsonDecode(log.payload) as Map<String, dynamic>,
            ),
          ).toJson(),
        )
        .toList();

    final nextCursor =
        visible.isNotEmpty ? visible.last.logId! : (cursor ?? 0);

    final responseBody = {
      'activities': responseActivities,
      'nextCursor': nextCursor,
      'hasMore': hasMore,
    };

    return Response.ok(
      jsonEncode(responseBody),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
