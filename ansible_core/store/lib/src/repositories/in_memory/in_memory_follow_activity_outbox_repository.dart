import '../../entities/outbound_follow_activity.dart';
import '../follow_activity_outbox_repository.dart';

class InMemoryFollowActivityOutboxRepository
    implements FollowActivityOutboxRepository {
  final Map<String, OutboundFollowActivity> _activities = {};

  @override
  Future<void> enqueue(OutboundFollowActivity activity) async {
    _activities[activity.outboxId] = activity;
  }

  @override
  Future<List<OutboundFollowActivity>> listQueued({int limit = 50}) async {
    final queued =
        _activities.values
            .where(
              (activity) =>
                  activity.status == OutboundFollowActivityStatus.queued,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return queued.take(limit).toList();
  }

  @override
  Future<void> markDelivering(String outboxId, DateTime now) async {
    final existing = _activities[outboxId];
    if (existing == null) return;
    _activities[outboxId] = OutboundFollowActivity(
      outboxId: existing.outboxId,
      activityId: existing.activityId,
      activityType: existing.activityType,
      targetInboxUri: existing.targetInboxUri,
      payloadJson: existing.payloadJson,
      status: OutboundFollowActivityStatus.delivering,
      attemptCount: existing.attemptCount + 1,
      lastError: existing.lastError,
      createdAt: existing.createdAt,
      updatedAt: now,
      deliveredAt: existing.deliveredAt,
    );
  }

  @override
  Future<void> markDelivered(String outboxId, DateTime now) async {
    final existing = _activities[outboxId];
    if (existing == null) return;
    _activities[outboxId] = OutboundFollowActivity(
      outboxId: existing.outboxId,
      activityId: existing.activityId,
      activityType: existing.activityType,
      targetInboxUri: existing.targetInboxUri,
      payloadJson: existing.payloadJson,
      status: OutboundFollowActivityStatus.delivered,
      attemptCount: existing.attemptCount,
      lastError: existing.lastError,
      createdAt: existing.createdAt,
      updatedAt: now,
      deliveredAt: now,
    );
  }

  @override
  Future<void> markFailed(
    String outboxId,
    String lastError,
    DateTime now,
  ) async {
    final existing = _activities[outboxId];
    if (existing == null) return;
    _activities[outboxId] = OutboundFollowActivity(
      outboxId: existing.outboxId,
      activityId: existing.activityId,
      activityType: existing.activityType,
      targetInboxUri: existing.targetInboxUri,
      payloadJson: existing.payloadJson,
      status: OutboundFollowActivityStatus.failed,
      attemptCount: existing.attemptCount,
      lastError: lastError,
      createdAt: existing.createdAt,
      updatedAt: now,
      deliveredAt: existing.deliveredAt,
    );
  }
}
