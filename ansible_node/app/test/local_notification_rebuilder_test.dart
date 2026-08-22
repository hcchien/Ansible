import 'package:ansible_node/services/local_notification_rebuilder.dart';
import 'package:ansible_store/ansible_store.dart' hide Board;
import 'package:ansible_store/ansible_store.dart' as store show Board;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const localDid = 'did:elix:local';
  const remoteDid = 'did:elix:remote';

  late AppDatabase db;
  late DriftNotificationRepository notifications;
  late DriftThreadRepository threads;
  late DriftPostRepository posts;
  late LocalNotificationRebuilder rebuilder;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    notifications = DriftNotificationRepository(db);
    threads = DriftThreadRepository(db);
    posts = DriftPostRepository(db);
    rebuilder = LocalNotificationRebuilder(
      notifications: notifications,
      threads: threads,
      posts: posts,
      messenger: DriftMessengerRepository(db),
      localDid: localDid,
    );

    final now = DateTime.utc(2026, 7, 22);
    await DriftBoardRepository(db).create(
      store.Board(
        id: 'board-1',
        slug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await threads.create(
      Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'Local thread',
        authorId: localDid,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  test('backfills verified replies from SQLite and is idempotent', () async {
    final now = DateTime.utc(2026, 7, 22, 1);
    await posts.create(
      Post(
        id: 'reply-1',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: remoteDid,
        content: 'reply',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
        signatureVerified: true,
      ),
    );

    await rebuilder.rebuild();
    await rebuilder.rebuild();

    final rows = await notifications.list();
    expect(rows, hasLength(1));
    expect(rows.single.type, NotificationType.replyToThread);
    expect(rows.single.dedupKey, 'reply:reply-1');
  });

  test(
    'backfills replies to a thread authored by a legacy DID alias',
    () async {
      const legacyDid = 'did:plc:legacy-local';
      await threads.create(
        Thread(
          id: 'legacy-thread',
          boardId: 'board-1',
          title: 'Migrated Forum Host thread',
          authorId: legacyDid,
          createdAt: DateTime.utc(2026, 7, 22),
          updatedAt: DateTime.utc(2026, 7, 22),
        ),
      );
      await posts.create(
        Post(
          id: 'legacy-reply',
          threadId: 'legacy-thread',
          boardId: 'board-1',
          authorId: remoteDid,
          content: 'reply after migration',
          createdAt: DateTime.utc(2026, 7, 22, 1),
          updatedAt: DateTime.utc(2026, 7, 22, 1),
          lastEditAt: DateTime.utc(2026, 7, 22, 1),
          signatureVerified: true,
        ),
      );
      rebuilder = LocalNotificationRebuilder(
        notifications: notifications,
        threads: threads,
        posts: posts,
        messenger: DriftMessengerRepository(db),
        localDid: localDid,
        localDidAliases: const [legacyDid],
      );

      await rebuilder.rebuild();

      expect(
        (await notifications.list()).map(
          (notification) => notification.dedupKey,
        ),
        contains('reply:legacy-reply'),
      );
    },
  );

  test('does not turn unverified local rows into notifications', () async {
    final now = DateTime.utc(2026, 7, 22, 1);
    await posts.create(
      Post(
        id: 'unverified-reply',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: remoteDid,
        content: 'untrusted',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      ),
    );

    await rebuilder.rebuild();

    expect(await notifications.list(), isEmpty);
  });

  test('rebuild preserves an existing read state', () async {
    final now = DateTime.utc(2026, 7, 22, 1);
    await posts.create(
      Post(
        id: 'reply-2',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: remoteDid,
        content: 'reply',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
        signatureVerified: true,
      ),
    );
    await rebuilder.rebuild();
    await notifications.markRead('reply:reply-2');

    await rebuilder.rebuild();

    expect((await notifications.list()).single.isRead, isTrue);
  });
}
