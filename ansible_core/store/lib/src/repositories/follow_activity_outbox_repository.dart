import '../entities/outbound_follow_activity.dart';

abstract class FollowActivityOutboxRepository {
  Future<void> enqueue(OutboundFollowActivity activity);
  Future<List<OutboundFollowActivity>> listQueued({int limit = 50});
  Future<void> markDelivering(String outboxId, DateTime now);
  Future<void> markDelivered(String outboxId, DateTime now);
  Future<void> markFailed(String outboxId, String lastError, DateTime now);
}
