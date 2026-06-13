import '../entities/notification.dart';

abstract class NotificationRepository {
  /// Inserts [notification] unless a row with the same `dedupKey` already
  /// exists. Re-synced ops therefore fold to a no-op and never duplicate a
  /// notification (and never reset its read state).
  ///
  /// Returns `true` when a new notification was created.
  Future<bool> upsertByDedupKey(AppNotification notification);

  /// Number of notifications whose `readAt` is null.
  Future<int> unreadCount();

  /// Notifications, newest first.
  Future<List<AppNotification>> list({int limit = 200});

  /// Marks a single notification read (no-op when already read).
  Future<void> markRead(String id, {DateTime? readAt});

  /// Marks every unread notification read.
  Future<void> markAllRead({DateTime? readAt});

  /// Deletes all notifications (user-initiated; local only).
  Future<void> deleteAll();
}
