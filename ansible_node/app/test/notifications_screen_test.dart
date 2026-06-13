import 'package:ansible_node/screens/notification_settings_screen.dart';
import 'package:ansible_node/screens/notifications_screen.dart';
import 'package:ansible_node/services/notification_preferences_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests assert zh-Hant copy (test locale falls back to zh-Hant).
void main() {
  const localDid = 'did:plc:local-user';
  const actorDid = 'did:plc:actor';

  AppNotification notification({
    required String id,
    required NotificationType type,
    DateTime? readAt,
  }) {
    return AppNotification(
      id: id,
      type: type,
      actorDid: actorDid,
      targetRef: id,
      threadId: type == NotificationType.replyToThread ? 'thread-1' : null,
      conversationId:
          type == NotificationType.messengerMessage ? actorDid : null,
      createdAt: DateTime.utc(2026, 6, 13),
      readAt: readAt,
      dedupKey: id,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    AppDatabase db,
    NotificationRepository repository,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          db: db,
          did: localDid,
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('renders one row per notification type', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final repo = InMemoryNotificationRepository();
    await repo.upsertByDedupKey(
      notification(id: 'n1', type: NotificationType.replyToThread),
    );
    await repo.upsertByDedupKey(
      notification(id: 'n2', type: NotificationType.newFollower),
    );
    await repo.upsertByDedupKey(
      notification(id: 'n3', type: NotificationType.messengerMessage),
    );

    await pumpScreen(tester, db, repo);

    expect(find.text('回覆了你的討論串'), findsOneWidget);
    expect(find.text('開始追蹤你'), findsOneWidget);
    expect(find.text('傳來一則私訊'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no notifications', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await pumpScreen(tester, db, InMemoryNotificationRepository());

    expect(find.text('目前沒有通知'), findsOneWidget);
  });

  testWidgets('mark-all-read clears the unread count', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final repo = InMemoryNotificationRepository();
    await repo.upsertByDedupKey(
      notification(id: 'n1', type: NotificationType.replyToThread),
    );
    await repo.upsertByDedupKey(
      notification(id: 'n2', type: NotificationType.newFollower),
    );
    expect(await repo.unreadCount(), 2);

    await pumpScreen(tester, db, repo);
    await tester.tap(find.text('全部已讀'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(await repo.unreadCount(), 0);
  });

  testWidgets('tapping a follower notification marks it read', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final repo = InMemoryNotificationRepository();
    await repo.upsertByDedupKey(
      notification(id: 'n1', type: NotificationType.newFollower),
    );

    await pumpScreen(tester, db, repo);
    await tester.tap(find.text('開始追蹤你'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(await repo.unreadCount(), 0);
  });

  testWidgets('settings toggles persist per category', (tester) async {
    final store = InMemoryNotificationPreferencesStore();
    final controller = NotificationPreferencesController(store: store);

    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(controller: controller)),
    );
    await tester.pump();

    final replyToggle = find.byKey(
      const Key('notification_toggle_reply'),
    );
    expect(replyToggle, findsOneWidget);

    // The row itself is not tappable — toggle the switch inside it.
    await tester.tap(
      find.descendant(of: replyToggle, matching: find.byType(Switch)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(await store.loadEnabled(NotificationCategory.reply), isFalse);
    expect(controller.isEnabled(NotificationCategory.reply), isFalse);
    // Other categories untouched (default on).
    expect(controller.isEnabled(NotificationCategory.follow), isTrue);
  });
}
