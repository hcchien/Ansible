import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/notification.dart';
import '../notification_repository.dart';

class DriftNotificationRepository implements NotificationRepository {
  final AppDatabase _db;

  DriftNotificationRepository(this._db);

  @override
  Future<bool> upsertByDedupKey(AppNotification notification) async {
    final existing =
        await (_db.select(_db.notifications)
              ..where((t) => t.dedupKey.equals(notification.dedupKey)))
            .getSingleOrNull();
    if (existing != null) {
      // Re-synced event: keep the original row (including read state).
      return false;
    }
    await _db
        .into(_db.notifications)
        .insert(
          NotificationsCompanion.insert(
            id: notification.id,
            type: notification.type.storageValue,
            actorDid: notification.actorDid,
            targetRef: notification.targetRef,
            boardId: Value(notification.boardId),
            threadId: Value(notification.threadId),
            postId: Value(notification.postId),
            conversationId: Value(notification.conversationId),
            createdAt: notification.createdAt,
            readAt: Value(notification.readAt),
            dedupKey: notification.dedupKey,
          ),
          // Belt and braces: a concurrent insert with the same dedup key
          // must never throw mid-sync.
          mode: InsertMode.insertOrIgnore,
        );
    return true;
  }

  @override
  Future<int> unreadCount() async {
    final countExp = _db.notifications.id.count();
    final query = _db.selectOnly(_db.notifications)
      ..addColumns([countExp])
      ..where(_db.notifications.readAt.isNull());
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Future<List<AppNotification>> list({int limit = 200}) async {
    final rows =
        await (_db.select(_db.notifications)
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit))
            .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> markRead(String id, {DateTime? readAt}) async {
    await (_db.update(_db.notifications)
          ..where((t) => t.id.equals(id) & t.readAt.isNull()))
        .write(
          NotificationsCompanion(
            readAt: Value(readAt ?? DateTime.now().toUtc()),
          ),
        );
  }

  @override
  Future<void> markAllRead({DateTime? readAt}) async {
    await (_db.update(_db.notifications)..where((t) => t.readAt.isNull()))
        .write(
          NotificationsCompanion(
            readAt: Value(readAt ?? DateTime.now().toUtc()),
          ),
        );
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete(_db.notifications).go();
  }

  AppNotification _toEntity(NotificationRow row) {
    return AppNotification(
      id: row.id,
      type: NotificationType.parse(row.type),
      actorDid: row.actorDid,
      targetRef: row.targetRef,
      boardId: row.boardId,
      threadId: row.threadId,
      postId: row.postId,
      conversationId: row.conversationId,
      createdAt: row.createdAt,
      readAt: row.readAt,
      dedupKey: row.dedupKey,
    );
  }
}
