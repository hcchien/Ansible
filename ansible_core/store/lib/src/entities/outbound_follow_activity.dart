enum OutboundFollowActivityType {
  follow,
  accept,
  reject,
  undo;

  static OutboundFollowActivityType parse(String value) {
    return OutboundFollowActivityType.values.firstWhere(
      (item) => item.name == value,
      orElse: () =>
          throw ArgumentError('Unknown OutboundFollowActivityType "$value"'),
    );
  }
}

enum OutboundFollowActivityStatus {
  queued,
  delivering,
  delivered,
  failed;

  static OutboundFollowActivityStatus parse(String value) {
    return OutboundFollowActivityStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () =>
          throw ArgumentError('Unknown OutboundFollowActivityStatus "$value"'),
    );
  }
}

class OutboundFollowActivity {
  final String outboxId;
  final String activityId;
  final OutboundFollowActivityType activityType;
  final String targetInboxUri;
  final String payloadJson;
  final OutboundFollowActivityStatus status;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deliveredAt;

  const OutboundFollowActivity({
    required this.outboxId,
    required this.activityId,
    required this.activityType,
    required this.targetInboxUri,
    required this.payloadJson,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
    this.deliveredAt,
  });
}
