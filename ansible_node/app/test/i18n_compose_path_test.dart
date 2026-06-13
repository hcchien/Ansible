import 'package:ansible_node/screens/posts_view_screen.dart';
import 'package:ansible_node/widgets/post_form_dialog.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression coverage for UX review finding #1: the core compose/read path
// must not leak hardcoded English. Widget tests assert zh-Hant copy because
// the test locale falls back to zh-Hant (uiCopy returns zh when no
// AppLocalizations is installed).
void main() {
  group('PostFormDialog zh-Hant copy', () {
    testWidgets('new-post dialog renders Chinese title and buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => const PostFormDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('發表貼文'), findsOneWidget); // title
      expect(find.text('內容'), findsOneWidget); // field label
      expect(find.text('取消'), findsOneWidget); // cancel
      expect(find.text('發表'), findsOneWidget); // post button
      expect(find.text('New Post'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('edit-post dialog renders Chinese edit title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) =>
                      const PostFormDialog(initialContent: 'hi there'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('編輯貼文'), findsOneWidget);
      expect(find.text('Edit Post'), findsNothing);
    });
  });

  group('PostsViewScreen zh-Hant empty state', () {
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
