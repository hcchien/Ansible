import 'package:ansible_node/screens/notification_settings_screen.dart';
import 'package:ansible_node/screens/notifications_screen.dart';
import 'package:ansible_node/services/handle_resolver.dart';
import 'package:ansible_node/services/notification_preferences_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
      threadId:
          type == NotificationType.replyToThread ||
              type == NotificationType.mention
          ? 'thread-1'
          : null,
      conversationId: type == NotificationType.messengerMessage
          ? actorDid
          : null,
      createdAt: DateTime.utc(2026, 6, 13),
      readAt: readAt,
      dedupKey: id,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    AppDatabase db,
    NotificationRepository repository, {
    VoidCallback? onUnreadChanged,
    PublicProfileResolver? profileResolver,
    HandleResolver? handleResolver,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          db: db,
          did: localDid,
          repository: repository,
          onUnreadChanged: onUnreadChanged,
          profileResolver: profileResolver,
          handleResolver: handleResolver,
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
    await repo.upsertByDedupKey(
      notification(id: 'n4', type: NotificationType.mention),
    );

    await pumpScreen(tester, db, repo);

    expect(find.text('回覆了你的討論串'), findsOneWidget);
    expect(find.text('開始追蹤你'), findsOneWidget);
    expect(find.text('傳來一則私訊'), findsOneWidget);
    expect(find.text('在回覆中提及了你'), findsOneWidget);
  });

  testWidgets(
    'notification actor uses display name before handle, alias, and DID',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      await DriftContactRepository(db).upsertContact(
        ContactRecord(
          subjectDid: actorDid,
          handle: 'stale-alice.elix.cool',
          displayName: '舊的本機名稱',
          localAlias: '本機別名',
          createdAt: DateTime.utc(2026, 6, 13),
          updatedAt: DateTime.utc(2026, 6, 13),
        ),
      );
      final repo = InMemoryNotificationRepository();
      await repo.upsertByDedupKey(
        notification(id: 'n1', type: NotificationType.newFollower),
      );
      final handleResolver = HandleResolver(
        baseUrl: 'https://relay.example',
        client: MockClient(
          (_) async => http.Response(
            '{"did":"$actorDid","handle":"alice.elix.cool"}',
            200,
          ),
        ),
      );
      final profileResolver = PublicProfileResolver(
        baseUrl: 'https://appview.example',
        handleResolver: handleResolver,
        client: MockClient(
          (_) async => http.Response(
            '{"display_name":"Alice","handle":"alice.elix.cool"}',
            200,
          ),
        ),
      );

      await pumpScreen(
        tester,
        db,
        repo,
        profileResolver: profileResolver,
        handleResolver: handleResolver,
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('@alice.elix.cool'), findsNothing);
      expect(find.text('舊的本機名稱'), findsNothing);
      expect(find.text('@stale-alice.elix.cool'), findsNothing);
      expect(find.text('本機別名'), findsNothing);
      expect(find.text(actorDid), findsNothing);
    },
  );

  testWidgets('notification actor falls back from handle to DID', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final contacts = DriftContactRepository(db);
    final repo = InMemoryNotificationRepository();
    await repo.upsertByDedupKey(
      notification(id: 'n1', type: NotificationType.newFollower),
    );

    await contacts.upsertContact(
      ContactRecord(
        subjectDid: actorDid,
        handle: 'alice.elix.cool',
        createdAt: DateTime.utc(2026, 6, 13),
        updatedAt: DateTime.utc(2026, 6, 13),
      ),
    );
    final offlineHandleResolver = HandleResolver(
      baseUrl: 'https://relay.example',
      client: MockClient((_) async => http.Response('', 404)),
    );
    final offlineProfileResolver = PublicProfileResolver(
      baseUrl: 'https://appview.example',
      handleResolver: offlineHandleResolver,
      client: MockClient((_) async => http.Response('', 404)),
    );
    await pumpScreen(
      tester,
      db,
      repo,
      profileResolver: offlineProfileResolver,
      handleResolver: offlineHandleResolver,
    );
    await tester.pumpAndSettle();
    expect(find.text('@alice.elix.cool'), findsOneWidget);
    expect(find.text(actorDid), findsNothing);

    const missingDid = 'did:plc:missing';
    await repo.upsertByDedupKey(
      AppNotification(
        id: 'n2',
        type: NotificationType.newFollower,
        actorDid: missingDid,
        targetRef: missingDid,
        createdAt: DateTime.utc(2026, 6, 13),
        dedupKey: 'n2',
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(
      tester,
      db,
      repo,
      profileResolver: offlineProfileResolver,
      handleResolver: offlineHandleResolver,
    );
    await tester.pumpAndSettle();
    expect(find.text(missingDid), findsOneWidget);
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

    var unreadChanges = 0;
    await pumpScreen(tester, db, repo, onUnreadChanged: () => unreadChanges++);
    await tester.tap(find.text('全部已讀'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(await repo.unreadCount(), 0);
    expect(unreadChanges, 1);
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

  testWidgets('renders a moderation outcome with the reason from the synced '
      'state', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    // The reason comes from the synced host moderation overlay.
    await DriftHostModerationStateRepository(db).replaceForBoard('board-1', [
      HostModerationState(
        localBoardId: 'board-1',
        targetKind: 'post',
        targetRef: 'post-1',
        action: 'removed',
        reasonCode: 'spam',
        updatedAt: DateTime.utc(2026, 6, 13),
      ),
    ]);
    final repo = InMemoryNotificationRepository();
    await repo.upsertByDedupKey(
      AppNotification(
        id: 'moderation:removed:post-1',
        type: NotificationType.moderationOutcome,
        actorDid: '',
        targetRef: 'post-1',
        boardId: 'board-1',
        threadId: 'thread-1',
        postId: 'post-1',
        createdAt: DateTime.utc(2026, 6, 13),
        dedupKey: 'moderation:removed:post-1',
      ),
    );

    await pumpScreen(tester, db, repo);

    expect(find.text('板務'), findsOneWidget);
    expect(find.text('你的內容已被板務處理（垃圾訊息）'), findsOneWidget);
  });

  testWidgets('renders a generic moderation label when the state entry is '
      'gone', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final repo = InMemoryNotificationRepository();
    await repo.upsertByDedupKey(
      AppNotification(
        id: 'moderation:locked:thread-1',
        type: NotificationType.moderationOutcome,
        actorDid: '',
        targetRef: 'thread-1',
        boardId: 'board-1',
        threadId: 'thread-1',
        createdAt: DateTime.utc(2026, 6, 13),
        dedupKey: 'moderation:locked:thread-1',
      ),
    );

    await pumpScreen(tester, db, repo);

    expect(find.text('你的內容已被板務處理'), findsOneWidget);
  });

  testWidgets('settings toggles persist per category', (tester) async {
    final store = InMemoryNotificationPreferencesStore();
    final controller = NotificationPreferencesController(store: store);

    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(controller: controller)),
    );
    await tester.pump();

    final replyToggle = find.byKey(const Key('notification_toggle_reply'));
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
