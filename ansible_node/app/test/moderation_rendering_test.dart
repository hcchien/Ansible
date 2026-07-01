import 'package:ansible_node/screens/posts_view_screen.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/widgets/posting_gate_notice.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests assert zh-Hant copy (test locale falls back to zh-Hant).
void main() {
  const localDid = 'did:plc:local-user';
  const otherDid = 'did:plc:someone-else';

  final now = DateTime.utc(2026, 6, 13);

  late AppDatabase db;
  late Thread thread;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    await DriftBoardRepository(db).create(
      Board(
        id: 'board-1',
        slug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
    thread = Thread(
      id: 'thread-1',
      boardId: 'board-1',
      title: 'A thread',
      authorId: otherDid,
      createdAt: now,
      updatedAt: now,
    );
    await DriftThreadRepository(db).create(thread);
  });

  tearDown(() => db.close());

  Future<void> seedPost({
    required String id,
    required String authorId,
    String content = 'original content',
  }) {
    return DriftPostRepository(db).create(
      Post(
        id: id,
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: authorId,
        content: content,
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      ),
    );
  }

  Future<void> seedModeration(List<HostModerationState> entries) {
    return DriftHostModerationStateRepository(
      db,
    ).replaceForBoard('board-1', entries);
  }

  HostModerationState removedPost(String postId, {String reason = 'spam'}) {
    return HostModerationState(
      localBoardId: 'board-1',
      targetKind: 'post',
      targetRef: postId,
      action: 'removed',
      reasonCode: reason,
      updatedAt: now,
    );
  }

  HostModerationState lockedThread({String reason = 'off_topic'}) {
    return HostModerationState(
      localBoardId: 'board-1',
      targetKind: 'thread',
      targetRef: 'thread-1',
      action: 'locked',
      reasonCode: reason,
      updatedAt: now,
    );
  }

  Future<void> pumpPostsView(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostsViewScreen(db: db, thread: thread, authorDid: localDid),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('someone else\'s removed post renders as a tombstone', (
    tester,
  ) async {
    await seedPost(id: 'post-1', authorId: otherDid, content: 'spammy text');
    await seedModeration([removedPost('post-1')]);

    await pumpPostsView(tester);

    expect(find.byKey(const Key('removed_post_tombstone_post-1')),
        findsOneWidget);
    expect(find.text('此留言已被板務移除（垃圾訊息）'), findsOneWidget);
    // Content (and author identity) is hidden.
    expect(find.text('spammy text'), findsNothing);
    expect(find.text(otherDid), findsNothing);
  });

  testWidgets('the author keeps their removed post visible with a notice', (
    tester,
  ) async {
    await seedPost(id: 'post-1', authorId: localDid, content: 'my own words');
    await seedModeration([removedPost('post-1', reason: 'harassment')]);

    await pumpPostsView(tester);

    // No tombstone for the author — content stays visible plus the
    // reason-coded removal notice (constitution-mandated visibility).
    expect(find.byKey(const Key('removed_post_tombstone_post-1')),
        findsNothing);
    expect(find.text('my own words'), findsOneWidget);
    expect(find.byKey(const Key('own_post_removal_notice_post-1')),
        findsOneWidget);
    expect(
      find.text('你的留言已被板務移除（騷擾或攻擊）。其他人看不到這則內容；你的本地副本不受影響。'),
      findsOneWidget,
    );
  });

  testWidgets('a locked thread shows the banner and disables the composer', (
    tester,
  ) async {
    await seedPost(id: 'post-1', authorId: otherDid);
    await seedModeration([lockedThread()]);

    await pumpPostsView(tester);

    expect(find.byKey(const Key('thread_locked_banner')), findsOneWidget);
    expect(find.text('此討論串已被板務鎖定（離題），暫停回覆'), findsOneWidget);
    expect(find.byKey(const Key('thread_locked_composer')), findsOneWidget);
    // The reply button is gone entirely.
    expect(find.text('發表貼文'), findsNothing);
  });

  testWidgets('a host lock wins over the posting tier gate', (tester) async {
    // Hosted projection with a tier gate the local user fails.
    await DriftHostedBoardRepository(db).upsertProjection(
      HostedBoardProjection(
        localBoardId: 'board-1',
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        canonicalBoardUri: 'https://relay.example/boards/hosted-1',
        remoteSlug: 'general',
        localSlug: 'general',
        title: 'General',
        postingPolicy: const {'min_post_tier': 'verified_human'},
        createdAt: now,
        updatedAt: now,
      ),
    );
    await seedModeration([lockedThread()]);

    await pumpPostsView(tester);

    expect(find.byKey(const Key('thread_locked_composer')), findsOneWidget);
    expect(find.byType(PostingGateNotice), findsNothing);
  });

  testWidgets('an unmoderated thread renders no banner or tombstones', (
    tester,
  ) async {
    await seedPost(id: 'post-1', authorId: otherDid, content: 'fine post');

    await pumpPostsView(tester);

    expect(find.byKey(const Key('thread_locked_banner')), findsNothing);
    expect(find.byKey(const Key('thread_locked_composer')), findsNothing);
    expect(find.text('fine post'), findsOneWidget);
    // The reply composer bar is present (replaces the old New Post button).
    expect(find.byKey(const Key('new_post_button')), findsOneWidget);
  });

  testWidgets('threads list shows a lock icon with a reason tooltip', (
    tester,
  ) async {
    await DriftThreadRepository(db).create(
      Thread(
        id: 'thread-2',
        boardId: 'board-1',
        title: 'Another thread',
        authorId: otherDid,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await seedModeration([lockedThread(reason: 'spam')]);

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadsListScreen(
          db: db,
          board: Board(
            id: 'board-1',
            slug: 'general',
            title: 'General',
            createdAt: now,
            updatedAt: now,
          ),
          localDid: localDid,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final lockIcon = find.byKey(const Key('thread_lock_icon_thread-1'));
    expect(lockIcon, findsOneWidget);
    // Only the locked thread carries the icon.
    expect(find.byKey(const Key('thread_lock_icon_thread-2')), findsNothing);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: lockIcon, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, '已被板務鎖定（垃圾訊息）');
  });
}
