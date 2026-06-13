/// Notification event types (Phase A: local projection only).
enum NotificationType {
  replyToThread('reply_to_thread'),
  replyToPost('reply_to_post'),
  newFollower('new_follower'),
  messengerMessage('messenger_message'),
  moderationOutcome('moderation_outcome');

  const NotificationType(this.storageValue);

  final String storageValue;

  static NotificationType parse(String value) {
    return NotificationType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unknown notification type',
      ),
    );
  }
}

/// A locally-projected notification. Never leaves the device.
class AppNotification {
  final String id;
  final NotificationType type;

  /// DID of the user who triggered the notification.
  final String actorDid;

  /// Id of the triggering entity (reply post id, follower DID, message id).
  final String targetRef;

  // Context refs for navigation (nullable per type).
  final String? boardId;
  final String? threadId;
  final String? postId;
  final String? conversationId;

  final DateTime createdAt;
  final DateTime? readAt;

  /// Stable identity of the underlying event; unique in storage so re-synced
  /// ops never duplicate notifications.
  final String dedupKey;

  const AppNotification({
    required this.id,
    required this.type,
    required this.actorDid,
    required this.targetRef,
    this.boardId,
    this.threadId,
    this.postId,
    this.conversationId,
    required this.createdAt,
    this.readAt,
    required this.dedupKey,
  });

  bool get isRead => readAt != null;

  AppNotification copyWith({DateTime? readAt}) {
    return AppNotification(
      id: id,
      type: type,
      actorDid: actorDid,
      targetRef: targetRef,
      boardId: boardId,
      threadId: threadId,
      postId: postId,
      conversationId: conversationId,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      dedupKey: dedupKey,
    );
  }
}
