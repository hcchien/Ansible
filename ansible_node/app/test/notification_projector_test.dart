import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/services/notification_preferences_controller.dart';
import 'package:ansible_node/services/notification_projector.dart';
import 'package:ansible_store/ansible_store.dart' hide Board;
import 'package:ansible_store/ansible_store.dart' as store show Board;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const localDid = 'did:plc:local-user';
  const otherDid = 'did:plc:someone-else';

  late AppDatabase db;
  late InMemoryNotificationRepository notifications;
  late NotificationProjector projector;

  Activity activity({
    String type = 'create',
    String entityType = 'post',
    required String entityId,
    String? boardId,
    String? threadId,
    String authorId = otherDid,
    Map<String, dynamic> payload = const {},
  }) {
    return Activity(
      activityId: 'activity-$entityId',
      type: type,
      entityType: entityType,
      entityId: entityId,
      boardId: boardId,
      threadId: threadId,
      authorId: authorId,
      createdAt: DateTime.utc(2026, 6, 13),
      payload: payload,
    );
  }

  Future<void> seedThread({required String authorId}) async {
    final now = DateTime.now().toUtc();
    await DriftBoardRepository(db).create(
      store.Board(
        id: 'board-1',
        slug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await DriftThreadRepository(db).create(
      Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'A thread',
        authorId: authorId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    notifications = InMemoryNotificationRepository();
    projector = NotificationProjector(
      notifications: notifications,
      localDid: localDid,
      threadRepository: DriftThreadRepository(db),
      postRepository: DriftPostRepository(db),
      contactRepository: DriftContactRepository(db),
    );
  });

  tearDown(() => db.close());

  test('reply in my thread emits reply_to_thread', () async {
    await seedThread(authorId: localDid);

    await projector.onSyncedActivity(
      activity(entityId: 'post-1', boardId: 'board-1', threadId: 'thread-1'),
    );

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.replyToThread);
    expect(all.single.actorDid, otherDid);
    expect(all.single.threadId, 'thread-1');
  });

  test('reply to my post emits reply_to_post', () async {
    await seedThread(authorId: otherDid);
    final now = DateTime.now().toUtc();
    await DriftPostRepository(db).create(
      Post(
        id: 'post-mine',
        boardId: 'board-1',
        threadId: 'thread-1',
        content: 'my post',
        authorId: localDid,
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      ),
    );

    await projector.onSyncedActivity(
      activity(
        entityId: 'post-2',
        boardId: 'board-1',
        threadId: 'thread-1',
        payload: {'parentPostId': 'post-mine'},
      ),
    );

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.replyToPost);
  });

  test('follow op targeting me emits new_follower', () async {
    await projector.onSyncedActivity(
      activity(entityType: 'follow', entityId: localDid),
    );

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.newFollower);
    expect(all.single.actorDid, otherDid);
  });

  test('replies in other people threads never notify', () async {
    await seedThread(authorId: otherDid);

    await projector.onSyncedActivity(
      activity(entityId: 'post-1', boardId: 'board-1', threadId: 'thread-1'),
    );

    expect(await notifications.list(), isEmpty);
  });

  test('self-actions never notify', () async {
    await seedThread(authorId: localDid);

    await projector.onSyncedActivity(
      activity(
        entityId: 'post-1',
        boardId: 'board-1',
        threadId: 'thread-1',
        authorId: localDid,
      ),
    );
    await projector.onSyncedActivity(
      activity(entityType: 'follow', entityId: localDid, authorId: localDid),
    );

    expect(await notifications.list(), isEmpty);
  });

  test('re-synced ops never duplicate (dedup key)', () async {
    await seedThread(authorId: localDid);
    final op = activity(
      entityId: 'post-1',
      boardId: 'board-1',
      threadId: 'thread-1',
    );

    await projector.onSyncedActivity(op);
    await projector.onSyncedActivity(op);
    await projector.onSyncedActivity(
      activity(entityType: 'follow', entityId: localDid),
    );
    await projector.onSyncedActivity(
      activity(entityType: 'follow', entityId: localDid),
    );

    expect(await notifications.list(), hasLength(2));
  });

  test('disabled category suppresses its notifications', () async {
    final prefs = NotificationPreferencesController(
      store: InMemoryNotificationPreferencesStore(
        enabled: {NotificationCategory.reply: false},
      ),
    );
    projector = NotificationProjector(
      notifications: notifications,
      localDid: localDid,
      threadRepository: DriftThreadRepository(db),
      postRepository: DriftPostRepository(db),
      contactRepository: DriftContactRepository(db),
      isCategoryEnabled: prefs.categoryEnabled,
    );
    await seedThread(authorId: localDid);

    await projector.onSyncedActivity(
      activity(entityId: 'post-1', boardId: 'board-1', threadId: 'thread-1'),
    );
    // Follow stays enabled.
    await projector.onSyncedActivity(
      activity(entityType: 'follow', entityId: localDid),
    );

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.newFollower);
  });

  test('messenger message emits notification once', () async {
    await projector.onMessengerMessage(
      senderDid: otherDid,
      messageId: 'msg-1',
    );
    await projector.onMessengerMessage(
      senderDid: otherDid,
      messageId: 'msg-1',
    );

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.messengerMessage);
    expect(all.single.conversationId, otherDid);
  });

  test('moderation outcome dedups on re-apply', () async {
    Future<void> emit() => projector.onModerationOutcome(
      targetKind: 'post',
      targetRef: 'post-1',
      boardId: 'board-1',
      threadId: 'thread-1',
      reasonCode: 'spam',
      action: 'removed',
    );

    await emit();
    await emit();

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.moderationOutcome);
    expect(all.single.dedupKey, 'moderation:removed:post-1');
    expect(all.single.postId, 'post-1');
    expect(all.single.threadId, 'thread-1');
  });

  test(
    'moderation outcome is always-on (no category toggle can suppress it)',
    () async {
      // Disable every toggleable category: constitution Base Rule 6 requires
      // the affected author to see moderation outcomes regardless.
      final prefs = NotificationPreferencesController(
        store: InMemoryNotificationPreferencesStore(
          enabled: {
            for (final category in NotificationCategory.values)
              category: false,
          },
        ),
      );
      projector = NotificationProjector(
        notifications: notifications,
        localDid: localDid,
        threadRepository: DriftThreadRepository(db),
        postRepository: DriftPostRepository(db),
        contactRepository: DriftContactRepository(db),
        isCategoryEnabled: prefs.categoryEnabled,
      );

      await projector.onModerationOutcome(
        targetKind: 'thread',
        targetRef: 'thread-1',
        boardId: 'board-1',
        reasonCode: 'off_topic',
        action: 'locked',
      );

      final all = await notifications.list();
      expect(all, hasLength(1));
      expect(all.single.type, NotificationType.moderationOutcome);
      // Thread targets navigate via threadId even when none is passed.
      expect(all.single.threadId, 'thread-1');
    },
  );

  test('blocked senders never notify for messenger messages', () async {
    final now = DateTime.now().toUtc();
    await DriftContactRepository(db).upsertContact(
      ContactRecord(
        subjectDid: otherDid,
        relationship: ContactRelationship.blocked,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await projector.onMessengerMessage(
      senderDid: otherDid,
      messageId: 'msg-1',
    );

    expect(await notifications.list(), isEmpty);
  });
}
