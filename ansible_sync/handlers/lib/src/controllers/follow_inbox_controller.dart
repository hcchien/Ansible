import 'dart:convert';

import 'package:ansible_ap/ansible_ap.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:shelf/shelf.dart';

class FollowInboxController {
  final FollowService? followService;
  final DateTime Function() _now;

  FollowInboxController({this.followService, DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  Future<Response> handleJson(Map<String, dynamic> json) async {
    try {
      final type = json['type'];
      if (type == 'Follow') {
        final activity = FollowActivity.fromJson(json);
        final result = await _routeFollow(activity);
        return _responseForResult(result);
      }
      if (type == 'Accept' || type == 'Reject') {
        final activity = FollowResponseActivity.fromJson(json);
        final result = await _routeFollowResponse(activity);
        return _responseForResult(result);
      }
      if (type == 'Undo') {
        final activity = UndoFollowActivity.fromJson(json);
        final result = await _routeUndo(activity);
        return _responseForResult(result);
      }

      return Response(
        400,
        body: jsonEncode({'error': 'unsupported_follow_activity'}),
      );
    } on FormatException {
      return Response(
        400,
        body: jsonEncode({'error': 'invalid_follow_activity'}),
      );
    }
  }

  Future<FollowResult> _routeFollow(FollowActivity activity) async {
    final service = followService;
    if (service == null) return const FollowResult.success('parsed');

    if (activity.isBoardFollow) {
      return service.followBoard(
        followerDid: activity.actor,
        boardId: activity.boardId!,
        boardSlug: activity.boardId!,
        actorUri: activity.object,
        displayName: activity.object,
        now: _now(),
      );
    }

    return service.followUser(
      followerDid: activity.actor,
      targetDid: activity.object.startsWith('did:') ? activity.object : null,
      actorUri: activity.object.startsWith('did:') ? null : activity.object,
      displayName: activity.object,
      now: _now(),
    );
  }

  Future<FollowResult> _routeFollowResponse(
    FollowResponseActivity activity,
  ) async {
    final service = followService;
    if (service == null) return const FollowResult.success('parsed');

    final target = await service.followRepository.getTargetByCanonicalUri(
      activity.object.object,
    );
    if (target == null) {
      return const FollowResult.targetNotFound('follow_not_found');
    }

    final transition = activity.type == FollowResponseType.accept
        ? service.acceptFollow
        : service.rejectFollow;
    return transition(
      followerDid: activity.object.actor,
      targetId: target.targetId,
      actorDid: activity.actor,
      now: _now(),
    );
  }

  Future<FollowResult> _routeUndo(UndoFollowActivity activity) async {
    final service = followService;
    if (service == null) return const FollowResult.success('parsed');

    final target = await service.followRepository.getTargetByCanonicalUri(
      activity.object.object,
    );
    if (target == null) {
      return const FollowResult.targetNotFound('follow_not_found');
    }

    return service.unfollow(
      followerDid: activity.object.actor,
      targetId: target.targetId,
      now: _now(),
    );
  }

  Response _responseForResult(FollowResult result) {
    return switch (result.status) {
      FollowResultStatus.success || FollowResultStatus.duplicate => Response.ok(
        jsonEncode({'status': 'accepted'}),
      ),
      FollowResultStatus.targetNotFound => Response(
        404,
        body: jsonEncode({'error': result.message ?? 'follow_not_found'}),
      ),
      FollowResultStatus.failed => Response(
        500,
        body: jsonEncode({'error': result.message ?? 'follow_failed'}),
      ),
    };
  }
}
