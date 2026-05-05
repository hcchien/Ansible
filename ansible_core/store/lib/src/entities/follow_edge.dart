import 'follow_target.dart';

enum FollowDirection {
  outbound,
  inbound;

  static FollowDirection parse(String value) =>
      FollowDirection.values.firstWhere(
        (item) => item.name == value,
        orElse: () => throw ArgumentError('Unknown FollowDirection "$value"'),
      );
}

enum FollowStatus {
  pending,
  accepted,
  rejected,
  cancelled,
  blocked,
  failed;

  static FollowStatus parse(String value) => FollowStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => throw ArgumentError('Unknown FollowStatus "$value"'),
  );
}

enum FollowVisibility {
  localOnly,
  federated;

  static FollowVisibility parse(String value) =>
      FollowVisibility.values.firstWhere(
        (item) => item.name == value,
        orElse: () => throw ArgumentError('Unknown FollowVisibility "$value"'),
      );
}

class FollowEdge {
  final String followId;
  final String followerDid;
  final String targetId;
  final FollowTargetType targetType;
  final FollowDirection direction;
  final FollowStatus status;
  final FollowVisibility visibility;
  final String? remoteActivityId;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acceptedAt;
  final DateTime? cancelledAt;

  const FollowEdge({
    required this.followId,
    required this.followerDid,
    required this.targetId,
    required this.targetType,
    required this.direction,
    required this.status,
    required this.visibility,
    required this.createdAt,
    required this.updatedAt,
    this.remoteActivityId,
    this.lastError,
    this.acceptedAt,
    this.cancelledAt,
  });
}
