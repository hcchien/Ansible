import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

AppNotification _notification({
  required String dedupKey,
  String? id,
  NotificationType type = NotificationType.replyToThread,
  String actorDid = 'did:key:alice',
  String targetRef = 'post-1',
  String? threadId,
  String? conversationId,
  DateTime? createdAt,
  DateTime? readAt,
}) {
  return AppNotification(
    id: id ?? dedupKey,
    type: type,
    actorDid: actorDid,
    targetRef: targetRef,
    threadId: threadId,
    conversationId: conversationId,
    createdAt: createdAt ?? DateTime.utc(2026, 6, 1, 12),
    readAt: readAt,
    dedupKey: dedupKey,
  );
}

void main() {
  group('NotificationRepository', () {
    for (final (label, makeRepo)
        in <(String, NotificationRepository Function(AppDatabase db))>[
          ('drift', DriftNotificationRepository.new),
          ('in-memory', (_) => InMemoryNotificationRepository()),
        ]) {
      group(label, () {
        late AppDatabase db;
        late NotificationRepository repo;

        setUp(() {
          db = AppDatabase(NativeDatabase.memory());
          repo = makeRepo(db);
        });

        tearDown(() => db.close());

        test('upsert by dedup key never duplicates re-synced events', () async {
          expect(
            await repo.upsertByDedupKey(_notification(dedupKey: 'reply:p1')),
            isTrue,
          );
          // Same event re-applied on a later sync pass.
          expect(
            await repo.upsertByDedupKey(_notification(dedupKey: 'reply:p1')),
            isFalse,
          );
          expect(
            await repo.upsertByDedupKey(_notification(dedupKey: 'reply:p2')),
            isTrue,
          );

          expect(await repo.list(), hasLength(2));
          expect(await repo.unreadCount(), 2);
        });

        test('re-synced event preserves read state', () async {
          final original = _notification(dedupKey: 'reply:p1');
          await repo.upsertByDedupKey(original);
          await repo.markRead(original.id);
          expect(await repo.unreadCount(), 0);

          await repo.upsertByDedupKey(_notification(dedupKey: 'reply:p1'));
          expect(await repo.unreadCount(), 0);
          expect(await repo.list(), hasLength(1));
        });

        test('lists newest first', () async {
          await repo.upsertByDedupKey(
            _notification(
              dedupKey: 'old',
              createdAt: DateTime.utc(2026, 6, 1, 8),
            ),
          );
          await repo.upsertByDedupKey(
            _notification(
              dedupKey: 'newest',
              createdAt: DateTime.utc(2026, 6, 1, 18),
            ),
          );
          await repo.upsertByDedupKey(
            _notification(
              dedupKey: 'middle',
              createdAt: DateTime.utc(2026, 6, 1, 12),
            ),
          );

          final listed = await repo.list();
          expect(listed.map((n) => n.dedupKey).toList(), [
            'newest',
            'middle',
            'old',
          ]);
        });

        test('markRead affects only the given notification', () async {
          await repo.upsertByDedupKey(_notification(dedupKey: 'a', id: 'n1'));
          await repo.upsertByDedupKey(_notification(dedupKey: 'b', id: 'n2'));

          await repo.markRead('n1', readAt: DateTime.utc(2026, 6, 2));

          expect(await repo.unreadCount(), 1);
          final listed = await repo.list();
          expect(listed.firstWhere((n) => n.id == 'n1').isRead, isTrue);
          expect(listed.firstWhere((n) => n.id == 'n2').isRead, isFalse);
        });

        test('markAllRead clears the unread count', () async {
          await repo.upsertByDedupKey(_notification(dedupKey: 'a', id: 'n1'));
          await repo.upsertByDedupKey(_notification(dedupKey: 'b', id: 'n2'));
          expect(await repo.unreadCount(), 2);

          await repo.markAllRead(readAt: DateTime.utc(2026, 6, 2));

          expect(await repo.unreadCount(), 0);
          expect((await repo.list()).every((n) => n.isRead), isTrue);
        });

        test('deleteAll removes every notification', () async {
          await repo.upsertByDedupKey(_notification(dedupKey: 'a'));
          await repo.upsertByDedupKey(
            _notification(
              dedupKey: 'b',
              type: NotificationType.messengerMessage,
              conversationId: 'did:key:bob',
            ),
          );

          await repo.deleteAll();

          expect(await repo.list(), isEmpty);
          expect(await repo.unreadCount(), 0);
        });

        test('round-trips all notification fields', () async {
          await repo.upsertByDedupKey(
            AppNotification(
              id: 'n1',
              type: NotificationType.replyToPost,
              actorDid: 'did:key:carol',
              targetRef: 'reply-post-9',
              boardId: 'board-1',
              threadId: 'thread-1',
              postId: 'reply-post-9',
              conversationId: null,
              createdAt: DateTime.utc(2026, 6, 1, 12),
              dedupKey: 'reply:reply-post-9',
            ),
          );

          final stored = (await repo.list()).single;
          expect(stored.id, 'n1');
          expect(stored.type, NotificationType.replyToPost);
          expect(stored.actorDid, 'did:key:carol');
          expect(stored.targetRef, 'reply-post-9');
          expect(stored.boardId, 'board-1');
          expect(stored.threadId, 'thread-1');
          expect(stored.postId, 'reply-post-9');
          expect(stored.conversationId, isNull);
          expect(stored.isRead, isFalse);
          expect(stored.dedupKey, 'reply:reply-post-9');
        });
      });
    }
  });
}
