import '../entities/follow_activity_event.dart';
import '../entities/follow_edge.dart';
import '../entities/follow_target.dart';

abstract class FollowRepository {
  Future<FollowTarget?> getTarget(String targetId);
  Future<FollowTarget?> getTargetByCanonicalUri(String canonicalUri);
  Future<FollowTarget?> getBoardTarget(String remoteNodeId, String boardId);
  Future<void> upsertTarget(FollowTarget target);
  Future<FollowEdge?> getEdge(
    String followerDid,
    String targetId,
    FollowDirection direction,
  );
  Future<List<FollowEdge>> listFollowing(
    String followerDid, {
    FollowTargetType? targetType,
  });
  Future<List<FollowEdge>> listOutbound(
    String followerDid, {
    FollowTargetType? targetType,
  });
  Future<List<FollowEdge>> listFollowers(String targetId);
  Future<List<FollowEdge>> listInbound(String targetId);
  Future<void> upsertEdge(FollowEdge edge);
  Future<void> updateEdgeStatus(
    String followId,
    FollowStatus status,
    DateTime now, {
    String? lastError,
  });
  Future<void> recordEvent(FollowActivityEvent event);
  Future<List<FollowActivityEvent>> listEvents(String followId);
}
