enum FollowActivityEventType {
  followRequested,
  followAccepted,
  followRejected,
  followCancelled,
  followBlocked,
  followFailed,
  followSynced;

  static FollowActivityEventType parse(String value) {
    return FollowActivityEventType.values.firstWhere(
      (item) => item.name == value,
      orElse: () =>
          throw ArgumentError('Unknown FollowActivityEventType "$value"'),
    );
  }
}

class FollowActivityEvent {
  final String eventId;
  final String followId;
  final FollowActivityEventType eventType;
  final String actorDid;
  final String? activityId;
  final String? message;
  final DateTime createdAt;

  const FollowActivityEvent({
    required this.eventId,
    required this.followId,
    required this.eventType,
    required this.actorDid,
    required this.createdAt,
    this.activityId,
    this.message,
  });
}
