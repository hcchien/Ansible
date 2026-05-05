enum FollowTargetType {
  user,
  board;

  static FollowTargetType parse(String value) {
    return FollowTargetType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown FollowTargetType "$value"'),
    );
  }
}

class FollowTarget {
  final String targetId;
  final FollowTargetType targetType;
  final String? canonicalUri;
  final String displayName;
  final String? handle;
  final String? did;
  final String? actorUri;
  final String? inboxUri;
  final String? outboxUri;
  final String? remoteNodeId;
  final String? boardId;
  final String? boardSlug;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const FollowTarget({
    required this.targetId,
    required this.targetType,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.canonicalUri,
    this.handle,
    this.did,
    this.actorUri,
    this.inboxUri,
    this.outboxUri,
    this.remoteNodeId,
    this.boardId,
    this.boardSlug,
    this.isDeleted = false,
  });
}
