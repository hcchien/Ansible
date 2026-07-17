import 'package:ansible_node/screens/post_composer_screen.dart';
import 'package:ansible_node/screens/posts_view_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression coverage for UX review finding #1: the core compose/read path
// must not leak hardcoded English. Widget tests assert zh-Hant copy because
// the test locale falls back to zh-Hant (uiCopy returns zh when no
// AppLocalizations is installed).
void main() {
  group('PostComposerScreen zh-Hant copy', () {
    testWidgets('new reply composer renders Chinese title and buttons', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PostComposerScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('發表貼文'), findsOneWidget); // title label
      expect(find.text('取消'), findsOneWidget); // cancel
      expect(find.text('發表'), findsOneWidget); // post button
      expect(find.text('輸入貼文內容'), findsOneWidget); // body hint
      expect(find.text('Cancel'), findsNothing);
      expect(find.textContaining('Write your reply'), findsNothing);
    });

    testWidgets('edit composer renders Chinese edit title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PostComposerScreen(initialContent: 'hi there')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('編輯貼文'), findsOneWidget);
      expect(find.text('Edit Post'), findsNothing);
    });
  });

  group('PostsViewScreen zh-Hant empty state', () {
    testWidgets('opening post renders when repository has no replies', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final now = DateTime.now().toUtc();
      final thread = Thread(
        id: 'thread-with-op',
        boardId: 'board-1',
        title: '原 PO 標題',
        authorId: 'did:plc:author',
        createdAt: now,
        updatedAt: now,
      );
      final openingPost = Post(
        id: 'opening-post',
        threadId: thread.id,
        boardId: thread.boardId,
        authorId: thread.authorId,
        content: '這是原 PO 的內容',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PostsViewScreen(
            db: db,
            thread: thread,
            openingPost: openingPost,
            authorDid: thread.authorId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('這是原 PO 的內容'), findsOneWidget);
      expect(find.text('還沒有貼文'), findsNothing);
    });

    testWidgets('empty board shows Chinese empty-state copy', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final now = DateTime.now().toUtc();
      final thread = Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: '測試討論串',
        authorId: 'did:plc:author',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PostsViewScreen(
            db: db,
            thread: thread,
            authorDid: 'did:plc:author',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('還沒有貼文'), findsOneWidget);
      expect(find.text('搶先發表第一則貼文'), findsOneWidget);
      expect(find.text('No posts yet'), findsNothing);
      expect(find.text('Be the first to post'), findsNothing);
    });
  });
}
