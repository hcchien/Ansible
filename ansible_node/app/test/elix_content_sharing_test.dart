import 'package:ansible_node/screens/posts_view_screen.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/services/elix_content_link.dart';
import 'package:ansible_node/services/elix_content_router.dart';
import 'package:ansible_store/ansible_store.dart' hide Board, Thread;
import 'package:ansible_store/ansible_store.dart' as store show Board, Thread;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests assert zh-Hant copy because the test locale falls back to
// zh-Hant (see existing screen tests, e.g. posting_gate_test.dart).
void main() {
  const localDid = 'did:plc:share-test-user';
  const canonicalBoardUri = 'https://relay.example/boards/hosted-1';
  const frontendBaseUrl = 'https://web.example/app';

  // --- Pure URL construction ------------------------------------------------

  group('ElixContentLink URL construction', () {
    test('board URL is built from the public frontend origin', () {
      expect(
        ElixContentLink.boardUrl(
          frontendBaseUrl: frontendBaseUrl,
          boardId: 'hosted-1',
        ),
        'https://web.example/boards/hosted-1',
      );
    });

    test('thread URL appends the thread segment under the board', () {
      expect(
        ElixContentLink.threadUrl(
          frontendBaseUrl: frontendBaseUrl,
          boardId: 'hosted-1',
          threadId: 'thread-9',
        ),
        'https://web.example/boards/hosted-1/threads/thread-9',
      );
    });

    test('returns null when the frontend URL has no usable origin', () {
      expect(
        ElixContentLink.boardUrl(
          frontendBaseUrl: 'not a url',
          boardId: 'hosted-1',
        ),
        isNull,
      );
    });
  });

  // --- Deep-link parsing ----------------------------------------------------

  group('ElixContentLink.parse', () {
    test('parses a https thread link to a thread ref', () {
      final ref = ElixContentLink.parse(
        Uri.parse('https://relay.example/boards/hosted-1/threads/thread-9'),
      );
      expect(ref, isNotNull);
      expect(ref!.isThread, isTrue);
      expect(ref.boardId, 'hosted-1');
      expect(ref.threadId, 'thread-9');
    });

    test('parses a custom-scheme board link to a board ref', () {
      final ref = ElixContentLink.parse(
        Uri.parse('trisaura://content/boards/hosted-1'),
      );
      expect(ref, isNotNull);
      expect(ref!.isThread, isFalse);
      expect(ref.boardId, 'hosted-1');
    });

    test('rejects non-content links', () {
      expect(
        ElixContentLink.parse(
          Uri.parse('trisaura://web-session/approve?challenge_id=x'),
        ),
        isNull,
      );
      expect(
        ElixContentLink.parse(Uri.parse('https://relay.example/')),
        isNull,
      );
    });
  });

  // --- DB-backed helpers ----------------------------------------------------

  Future<store.Board> seedHostedBoard(AppDatabase db) async {
    final now = DateTime.now().toUtc();
    final board = store.Board(
      id: 'board-local',
      slug: 'general',
      title: 'General',
      createdAt: now,
      updatedAt: now,
    );
    await DriftBoardRepository(db).create(board);
    await DriftHostedBoardRepository(db).upsertProjection(
      HostedBoardProjection(
        localBoardId: board.id,
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        canonicalBoardUri: canonicalBoardUri,
        remoteSlug: 'general',
        localSlug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
    return board;
  }

  Future<store.Thread> seedThread(AppDatabase db, store.Board board) async {
    final now = DateTime.now().toUtc();
    final thread = store.Thread(
      id: 'thread-9',
      boardId: board.id,
      title: '分享測試討論串',
      authorId: 'did:plc:author',
      createdAt: now,
      updatedAt: now,
    );
    await DriftThreadRepository(db).create(thread);
    return thread;
  }

  // --- Share action invokes the seam with the constructed URL ---------------

  group('Share action', () {
    testWidgets('thread share invokes the share API with the public URL', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedHostedBoard(db);
      final thread = await seedThread(db, board);

      String? sharedText;
      String? sharedSubject;
      await tester.pumpWidget(
        MaterialApp(
          home: PostsViewScreen(
            db: db,
            thread: thread,
            authorDid: localDid,
            shareSheet: (text, {subject, sharePositionOrigin}) async {
              sharedText = text;
              sharedSubject = subject;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final shareButton = find.byKey(const Key('share_thread_button'));
      expect(shareButton, findsOneWidget);
      // zh-Hant tooltip.
      expect(tester.widget<IconButton>(shareButton).tooltip, '分享討論串');

      await tester.tap(shareButton);
      await tester.pump();

      expect(
        sharedText,
        'https://forum.elix.cool/boards/hosted-1/threads/thread-9',
      );
      expect(sharedSubject, '分享測試討論串');

      sharedText = null;
      await tester.tap(find.byKey(const Key('share_thread_action')));
      await tester.pump();
      expect(
        sharedText,
        'https://forum.elix.cool/boards/hosted-1/threads/thread-9',
      );
    });

    testWidgets('board share invokes the share API with the public board URL', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedHostedBoard(db);

      String? sharedText;
      await tester.pumpWidget(
        MaterialApp(
          home: ThreadsListScreen(
            db: db,
            board: board,
            localDid: localDid,
            shareSheet: (text, {subject, sharePositionOrigin}) async {
              sharedText = text;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final shareButton = find.byKey(const Key('share_board_button'));
      expect(shareButton, findsOneWidget);
      expect(tester.widget<IconButton>(shareButton).tooltip, '分享看板');

      await tester.tap(shareButton);
      await tester.pump();

      expect(sharedText, 'https://forum.elix.cool/boards/hosted-1');
    });

    testWidgets('local-only thread shows no share affordance', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final now = DateTime.now().toUtc();
      final thread = store.Thread(
        id: 'thread-local',
        boardId: 'board-local-only',
        title: 'Local thread',
        authorId: 'did:plc:author',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PostsViewScreen(db: db, thread: thread, authorDid: localDid),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('share_thread_button')), findsNothing);
    });
  });

  // --- Deep-link router maps a URL to the right content ----------------------

  group('ElixContentRouter', () {
    test('a thread URL resolves to the local thread', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedHostedBoard(db);
      await seedThread(db, board);

      final ref = ElixContentLink.parse(
        Uri.parse('https://relay.example/boards/hosted-1/threads/thread-9'),
      );
      final resolution = await ElixContentRouter(db).resolve(ref!);

      expect(resolution, isA<ResolvedThread>());
      expect((resolution as ResolvedThread).thread.id, 'thread-9');
      expect(resolution.thread.title, '分享測試討論串');
    });

    test(
      'a board URL resolves to the local board via its projection',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => db.close());
        await seedHostedBoard(db);

        final ref = ElixContentLink.parse(
          Uri.parse('trisaura://content/boards/hosted-1'),
        );
        final resolution = await ElixContentRouter(db).resolve(ref!);

        expect(resolution, isA<ResolvedBoard>());
        expect((resolution as ResolvedBoard).board.id, 'board-local');
      },
    );

    test('an unknown thread surfaces ContentUnavailable', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final ref = ElixContentLink.parse(
        Uri.parse('https://relay.example/boards/hosted-1/threads/missing'),
      );
      final resolution = await ElixContentRouter(db).resolve(ref!);

      expect(resolution, isA<ContentUnavailable>());
    });
  });
}
