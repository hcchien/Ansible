import 'dart:convert';

import 'package:ansible_ap/ansible_ap.dart';
import 'package:ansible_store/ansible_store.dart';

import 'follow_result.dart';

abstract class FollowIdFactory {
  String next(String prefix);
}

class UtcTimestampFollowIdFactory implements FollowIdFactory {
  @override
  String next(String prefix) {
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}';
  }
}

class FollowService {
  final FollowRepository followRepository;
  final FollowActivityOutboxRepository outboxRepository;
  final BoardSyncConfigRepository boardSyncConfigRepository;
  // Optional: when provided, unfollowing a user purges that author's locally
  // synced posts/content that exist only because of the follow (exit/revoke).
  final PostRepository? postRepository;
  final ContentItemRepository? contentItemRepository;
  final FollowIdFactory idFactory;

  FollowService({
    required this.followRepository,
    required this.outboxRepository,
    required this.boardSyncConfigRepository,
    this.postRepository,
    this.contentItemRepository,
    FollowIdFactory? idFactory,
  }) : idFactory = idFactory ?? UtcTimestampFollowIdFactory();

  Future<FollowResult> followUser({
    required String followerDid,
    String? targetDid,
    String? actorUri,
    String? inboxUri,
    required String displayName,
    required DateTime now,
  }) async {
    final canonicalUri = _firstNonEmpty([actorUri, targetDid]);
    if (canonicalUri == null) {
      return const FollowResult.targetNotFound('target_not_found');
    }

    final target = await _upsertTarget(
      targetType: FollowTargetType.user,
      canonicalUri: canonicalUri,
      displayName: displayName,
      targetDid: targetDid,
      actorUri: actorUri,
      inboxUri: inboxUri,
      now: now,
    );

    return _followTarget(
      followerDid: followerDid,
      target: target,
      object: actorUri ?? canonicalUri,
      now: now,
    );
  }

  Future<FollowResult> followBoard({
    required String followerDid,
    String? remoteNodeId,
    required String boardId,
    required String boardSlug,
    String? actorUri,
    String? inboxUri,
    required String displayName,
    required DateTime now,
  }) async {
    if (boardId.isEmpty) {
      return const FollowResult.targetNotFound('board_not_found');
    }

    final canonicalUri =
        actorUri ??
        (remoteNodeId == null
            ? 'local://boards/$boardId'
            : 'remote://$remoteNodeId/boards/$boardId');
    final existingTarget = remoteNodeId == null
        ? await followRepository.getTargetByCanonicalUri(canonicalUri)
        : await followRepository.getBoardTarget(remoteNodeId, boardId);
    final target = FollowTarget(
      targetId: existingTarget?.targetId ?? idFactory.next('follow-target'),
      targetType: FollowTargetType.board,
      canonicalUri: canonicalUri,
      displayName: displayName,
      actorUri: actorUri,
      inboxUri: inboxUri,
      remoteNodeId: remoteNodeId,
      boardId: boardId,
      boardSlug: boardSlug,
      createdAt: existingTarget?.createdAt ?? now,
      updatedAt: now,
    );
    await followRepository.upsertTarget(target);

    if (remoteNodeId != null) {
      await boardSyncConfigRepository.toggleSync(remoteNodeId, boardId, true);
    }

    return _followTarget(
      followerDid: followerDid,
      target: target,
      object: actorUri ?? canonicalUri,
      now: now,
    );
  }

  Future<FollowResult> acceptFollow({
    required String followerDid,
    required String targetId,
    required String actorDid,
    required DateTime now,
  }) async {
    return _transitionFollow(
      followerDid: followerDid,
      targetId: targetId,
      actorDid: actorDid,
      status: FollowStatus.accepted,
      eventType: FollowActivityEventType.followAccepted,
      now: now,
    );
  }

  Future<FollowResult> rejectFollow({
    required String followerDid,
    required String targetId,
    required String actorDid,
    required DateTime now,
  }) async {
    return _transitionFollow(
      followerDid: followerDid,
      targetId: targetId,
      actorDid: actorDid,
      status: FollowStatus.rejected,
      eventType: FollowActivityEventType.followRejected,
      now: now,
    );
  }

  Future<FollowResult> blockTarget({
    required String followerDid,
    required String targetId,
    required String actorDid,
    required DateTime now,
  }) async {
    return _transitionFollow(
      followerDid: followerDid,
      targetId: targetId,
      actorDid: actorDid,
      status: FollowStatus.blocked,
      eventType: FollowActivityEventType.followBlocked,
      now: now,
    );
  }

  Future<FollowResult> unfollow({
    required String followerDid,
    required String targetId,
    required DateTime now,
  }) async {
    final edge = await followRepository.getEdge(
      followerDid,
      targetId,
      FollowDirection.outbound,
    );
    if (edge == null) {
      return const FollowResult.targetNotFound('follow_not_found');
    }

    final target = await followRepository.getTarget(targetId);
    if (target == null) {
      return const FollowResult.targetNotFound('target_not_found');
    }

    if (target.remoteNodeId != null && target.boardId != null) {
      await boardSyncConfigRepository.toggleSync(
        target.remoteNodeId!,
        target.boardId!,
        false,
      );
    }

    if (edge.visibility == FollowVisibility.federated &&
        target.inboxUri != null &&
        target.inboxUri!.isNotEmpty) {
      await _enqueueUndo(
        edge: edge,
        target: target,
        actorDid: followerDid,
        now: now,
      );
    }

    await followRepository.updateEdgeStatus(
      edge.followId,
      FollowStatus.cancelled,
      now,
    );
    await _recordEvent(
      followId: edge.followId,
      eventType: FollowActivityEventType.followCancelled,
      actorDid: followerDid,
      activityId: edge.remoteActivityId,
      now: now,
    );

    if (target.targetType == FollowTargetType.user) {
      await _purgeFollowOnlyAuthorContent(followerDid, target);
    }
    return FollowResult.success(edge.followId);
  }

  /// Deletes an unfollowed user's locally-synced content that exists only
  /// because of the follow: posts not justified by a board the user still
  /// follows, and synced murmur/note items. The user's own authored content has
  /// a different author DID and is never matched.
  Future<void> _purgeFollowOnlyAuthorContent(
    String followerDid,
    FollowTarget target,
  ) async {
    final authorDid = target.did ?? target.canonicalUri;
    if (authorDid == null || authorDid.isEmpty) return;

    final postRepo = postRepository;
    if (postRepo != null) {
      final keptBoardIds = await _keptBoardIds(followerDid);
      for (final post in await postRepo.list()) {
        if (post.authorId == authorDid &&
            !keptBoardIds.contains(post.boardId)) {
          await postRepo.delete(post.id);
        }
      }
    }

    final contentRepo = contentItemRepository;
    if (contentRepo != null) {
      for (final item in await contentRepo.list()) {
        if (item.authorDid == authorDid && !item.localOnly) {
          await contentRepo.delete(item.id);
        }
      }
    }
  }

  Future<Set<String>> _keptBoardIds(String followerDid) async {
    final edges = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.board,
    );
    final ids = <String>{};
    for (final edge in edges.where(
      (edge) => edge.status == FollowStatus.accepted,
    )) {
      final t = await followRepository.getTarget(edge.targetId);
      final boardId = t?.boardId;
      if (boardId != null && boardId.isNotEmpty) {
        ids.add(boardId);
      }
    }
    return ids;
  }

  Future<FollowResult> retryFollow({
    required String followerDid,
    required String targetId,
    required DateTime now,
  }) async {
    final edge = await followRepository.getEdge(
      followerDid,
      targetId,
      FollowDirection.outbound,
    );
    if (edge == null) {
      return const FollowResult.targetNotFound('follow_not_found');
    }
    if (edge.status != FollowStatus.failed) {
      return FollowResult.duplicate(edge.followId);
    }

    final target = await followRepository.getTarget(targetId);
    if (target == null) {
      return const FollowResult.targetNotFound('target_not_found');
    }

    final activityId =
        edge.remoteActivityId ?? 'local://activities/follow/${edge.followId}';
    if (target.inboxUri != null && target.inboxUri!.isNotEmpty) {
      await _enqueueFollow(
        activityId: activityId,
        followerDid: followerDid,
        target: target,
        object: target.actorUri ?? target.canonicalUri ?? target.targetId,
        now: now,
      );
    }

    await followRepository.updateEdgeStatus(
      edge.followId,
      FollowStatus.pending,
      now,
    );
    await _recordEvent(
      followId: edge.followId,
      eventType: FollowActivityEventType.followRequested,
      actorDid: followerDid,
      activityId: activityId,
      now: now,
    );
    return FollowResult.success(edge.followId);
  }

  Future<FollowTarget> _upsertTarget({
    required FollowTargetType targetType,
    required String canonicalUri,
    required String displayName,
    required DateTime now,
    String? targetDid,
    String? actorUri,
    String? inboxUri,
  }) async {
    final existingTarget = await followRepository.getTargetByCanonicalUri(
      canonicalUri,
    );
    final target = FollowTarget(
      targetId: existingTarget?.targetId ?? idFactory.next('follow-target'),
      targetType: targetType,
      canonicalUri: canonicalUri,
      displayName: displayName,
      did: targetDid,
      actorUri: actorUri,
      inboxUri: inboxUri,
      createdAt: existingTarget?.createdAt ?? now,
      updatedAt: now,
    );
    await followRepository.upsertTarget(target);
    return target;
  }

  Future<FollowResult> _followTarget({
    required String followerDid,
    required FollowTarget target,
    required String object,
    required DateTime now,
  }) async {
    final existingEdge = await followRepository.getEdge(
      followerDid,
      target.targetId,
      FollowDirection.outbound,
    );
    if (existingEdge != null && existingEdge.status != FollowStatus.cancelled) {
      return FollowResult.duplicate(existingEdge.followId);
    }

    final federated = target.inboxUri != null && target.inboxUri!.isNotEmpty;
    final followId = existingEdge?.followId ?? idFactory.next('follow');
    final activityId = federated ? 'local://activities/follow/$followId' : null;
    await followRepository.upsertEdge(
      FollowEdge(
        followId: followId,
        followerDid: followerDid,
        targetId: target.targetId,
        targetType: target.targetType,
        direction: FollowDirection.outbound,
        status: federated ? FollowStatus.pending : FollowStatus.accepted,
        visibility: federated
            ? FollowVisibility.federated
            : FollowVisibility.localOnly,
        remoteActivityId: activityId,
        createdAt: existingEdge?.createdAt ?? now,
        updatedAt: now,
        acceptedAt: federated ? null : now,
      ),
    );

    if (federated) {
      await _enqueueFollow(
        activityId: activityId!,
        followerDid: followerDid,
        target: target,
        object: object,
        now: now,
      );
    }

    await _recordEvent(
      followId: followId,
      eventType: FollowActivityEventType.followRequested,
      actorDid: followerDid,
      activityId: activityId,
      now: now,
    );
    return FollowResult.success(followId);
  }

  Future<FollowResult> _transitionFollow({
    required String followerDid,
    required String targetId,
    required String actorDid,
    required FollowStatus status,
    required FollowActivityEventType eventType,
    required DateTime now,
  }) async {
    final edge = await followRepository.getEdge(
      followerDid,
      targetId,
      FollowDirection.outbound,
    );
    if (edge == null) {
      return const FollowResult.targetNotFound('follow_not_found');
    }

    await followRepository.updateEdgeStatus(edge.followId, status, now);
    await _recordEvent(
      followId: edge.followId,
      eventType: eventType,
      actorDid: actorDid,
      activityId: edge.remoteActivityId,
      now: now,
    );
    return FollowResult.success(edge.followId);
  }

  Future<void> _enqueueFollow({
    required String activityId,
    required String followerDid,
    required FollowTarget target,
    required String object,
    required DateTime now,
  }) async {
    final activity = target.targetType == FollowTargetType.board
        ? FollowActivity.board(
            id: activityId,
            actor: followerDid,
            object: object,
            boardId: target.boardId!,
            published: now,
          )
        : FollowActivity.user(
            id: activityId,
            actor: followerDid,
            object: object,
            published: now,
          );

    await outboxRepository.enqueue(
      OutboundFollowActivity(
        outboxId: idFactory.next('follow-outbox'),
        activityId: activityId,
        activityType: OutboundFollowActivityType.follow,
        targetInboxUri: target.inboxUri!,
        payloadJson: jsonEncode(activity.toJson()),
        status: OutboundFollowActivityStatus.queued,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _enqueueUndo({
    required FollowEdge edge,
    required FollowTarget target,
    required String actorDid,
    required DateTime now,
  }) async {
    final follow = FollowActivity(
      id: edge.remoteActivityId ?? 'local://activities/follow/${edge.followId}',
      actor: actorDid,
      object: target.actorUri ?? target.canonicalUri ?? target.targetId,
      published: null,
      isBoardFollow: target.targetType == FollowTargetType.board,
      boardId: target.boardId,
    );
    final activityId = 'local://activities/undo/${edge.followId}';
    final activity = UndoFollowActivity(
      id: activityId,
      actor: actorDid,
      object: follow,
      published: now,
    );
    await outboxRepository.enqueue(
      OutboundFollowActivity(
        outboxId: idFactory.next('follow-outbox'),
        activityId: activityId,
        activityType: OutboundFollowActivityType.undo,
        targetInboxUri: target.inboxUri!,
        payloadJson: jsonEncode(activity.toJson()),
        status: OutboundFollowActivityStatus.queued,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _recordEvent({
    required String followId,
    required FollowActivityEventType eventType,
    required String actorDid,
    required DateTime now,
    String? activityId,
    String? message,
  }) async {
    await followRepository.recordEvent(
      FollowActivityEvent(
        eventId: idFactory.next('follow-event'),
        followId: followId,
        eventType: eventType,
        actorDid: actorDid,
        activityId: activityId,
        message: message,
        createdAt: now,
      ),
    );
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
