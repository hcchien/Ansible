import '../../entities/follow_activity_event.dart';
import '../../entities/follow_edge.dart';
import '../../entities/follow_target.dart';
import '../follow_repository.dart';

class InMemoryFollowRepository implements FollowRepository {
  final Map<String, FollowTarget> _targets = {};
  final Map<String, FollowEdge> _edges = {};
  final Map<String, List<FollowActivityEvent>> _eventsByFollow = {};

  @override
  Future<FollowTarget?> getTarget(String targetId) async {
    return _targets[targetId];
  }

  @override
  Future<FollowTarget?> getTargetByCanonicalUri(String canonicalUri) async {
    for (final target in _targets.values) {
      if (target.canonicalUri == canonicalUri) return target;
    }
    return null;
  }

  @override
  Future<FollowTarget?> getBoardTarget(
    String remoteNodeId,
    String boardId,
  ) async {
    for (final target in _targets.values) {
      if (target.remoteNodeId == remoteNodeId && target.boardId == boardId) {
        return target;
      }
    }
    return null;
  }

  @override
  Future<void> upsertTarget(FollowTarget target) async {
    _targets[target.targetId] = target;
  }

  @override
  Future<FollowEdge?> getEdge(
    String followerDid,
    String targetId,
    FollowDirection direction,
  ) async {
    for (final edge in _edges.values) {
      if (edge.followerDid == followerDid &&
          edge.targetId == targetId &&
          edge.direction == direction) {
        return edge;
      }
    }
    return null;
  }

  @override
  Future<List<FollowEdge>> listFollowing(
    String followerDid, {
    FollowTargetType? targetType,
  }) async {
    final edges =
        _edges.values
            .where(
              (edge) =>
                  edge.followerDid == followerDid &&
                  edge.direction == FollowDirection.outbound &&
                  edge.status == FollowStatus.accepted &&
                  (targetType == null || edge.targetType == targetType),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return edges;
  }

  @override
  Future<List<FollowEdge>> listOutbound(
    String followerDid, {
    FollowTargetType? targetType,
  }) async {
    final edges =
        _edges.values
            .where(
              (edge) =>
                  edge.followerDid == followerDid &&
                  edge.direction == FollowDirection.outbound &&
                  (targetType == null || edge.targetType == targetType),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return edges;
  }

  @override
  Future<List<FollowEdge>> listFollowers(String targetId) async {
    final edges =
        _edges.values
            .where(
              (edge) =>
                  edge.targetId == targetId &&
                  edge.direction == FollowDirection.inbound &&
                  edge.status == FollowStatus.accepted,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return edges;
  }

  @override
  Future<List<FollowEdge>> listInbound(String targetId) async {
    final edges =
        _edges.values
            .where(
              (edge) =>
                  edge.targetId == targetId &&
                  edge.direction == FollowDirection.inbound,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return edges;
  }

  @override
  Future<void> upsertEdge(FollowEdge edge) async {
    _edges[edge.followId] = edge;
  }

  @override
  Future<void> updateEdgeStatus(
    String followId,
    FollowStatus status,
    DateTime now, {
    String? lastError,
  }) async {
    final existing = _edges[followId];
    if (existing == null) return;

    _edges[followId] = FollowEdge(
      followId: existing.followId,
      followerDid: existing.followerDid,
      targetId: existing.targetId,
      targetType: existing.targetType,
      direction: existing.direction,
      status: status,
      visibility: existing.visibility,
      remoteActivityId: existing.remoteActivityId,
      lastError: lastError,
      createdAt: existing.createdAt,
      updatedAt: now,
      acceptedAt: status == FollowStatus.accepted ? now : existing.acceptedAt,
      cancelledAt: status == FollowStatus.cancelled
          ? now
          : existing.cancelledAt,
    );
  }

  @override
  Future<void> recordEvent(FollowActivityEvent event) async {
    final events = _eventsByFollow.putIfAbsent(event.followId, () => []);
    final existingIndex = events.indexWhere(
      (item) => item.eventId == event.eventId,
    );
    if (existingIndex == -1) {
      events.add(event);
    } else {
      events[existingIndex] = event;
    }
  }

  @override
  Future<List<FollowActivityEvent>> listEvents(String followId) async {
    final events = List<FollowActivityEvent>.from(
      _eventsByFollow[followId] ?? const [],
    )..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return events;
  }
}
