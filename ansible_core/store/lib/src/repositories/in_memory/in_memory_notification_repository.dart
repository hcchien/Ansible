import '../../entities/notification.dart';
import '../notification_repository.dart';

class InMemoryNotificationRepository implements NotificationRepository {
  final Map<String, AppNotification> _byDedupKey = {};

  @override
  Future<bool> upsertByDedupKey(AppNotification notification) async {
    if (_byDedupKey.containsKey(notification.dedupKey)) return false;
    _byDedupKey[notification.dedupKey] = notification;
    return true;
  }

  @override
  Future<int> unreadCount() async {
    return _byDedupKey.values.where((n) => !n.isRead).length;
  }

  @override
  Future<List<AppNotification>> list({int limit = 200}) async {
    final sorted = _byDedupKey.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<void> markRead(String id, {DateTime? readAt}) async {
    for (final entry in _byDedupKey.entries) {
      final notification = entry.value;
      if (notification.id == id && !notification.isRead) {
        _byDedupKey[entry.key] = notification.copyWith(
          readAt: readAt ?? DateTime.now().toUtc(),
        );
        return;
      }
    }
  }

  @override
  Future<void> markAllRead({DateTime? readAt}) async {
    final at = readAt ?? DateTime.now().toUtc();
    for (final entry in _byDedupKey.entries.toList()) {
      if (!entry.value.isRead) {
        _byDedupKey[entry.key] = entry.value.copyWith(readAt: at);
      }
    }
  }

  @override
  Future<void> deleteAll() async {
    _byDedupKey.clear();
  }
}
