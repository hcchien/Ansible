import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/widgets/publication_time.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('board orders by reply publication, not insertion or edit time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final start = DateTime.utc(2026, 9, 1);
    final board = Board(
      id: 'b',
      slug: 'b',
      title: 'Board',
      createdAt: start,
      updatedAt: start,
    );
    await DriftBoardRepository(db).create(board);
    for (final id in ['older', 'newer']) {
      final created = start.add(Duration(days: id == 'newer' ? 1 : 0));
      await DriftThreadRepository(db).create(
        Thread(
          id: id,
          boardId: 'b',
          title: id,
          authorId: 'did:test:a',
          createdAt: created,
          updatedAt: start.add(const Duration(days: 20)),
        ),
      );
      await DriftPostRepository(db).create(
        Post(
          id: 'op-$id',
          threadId: id,
          boardId: 'b',
          authorId: 'did:test:a',
          content: 'Opening',
          createdAt: created,
          updatedAt: created,
          lastEditAt: created,
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadsListScreen(db: db, board: board),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('newer')).dy,
      lessThan(tester.getTopLeft(find.text('older')).dy),
    );
    final replyAt = start.add(const Duration(days: 3));
    await DriftPostRepository(db).create(
      Post(
        id: 'reply',
        threadId: 'older',
        boardId: 'b',
        authorId: 'did:test:a',
        content: 'Reply',
        createdAt: replyAt,
        updatedAt: replyAt,
        lastEditAt: replyAt,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadsListScreen(db: db, board: board),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('older')).dy,
      lessThan(tester.getTopLeft(find.text('newer')).dy),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });

  testWidgets('publication time includes local date and minutes', (
    tester,
  ) async {
    final date = DateTime(2026, 9, 6, 13, 4);
    await tester.pumpWidget(
      MaterialApp(
        home: PublicationTime(date: date, color: Colors.grey),
      ),
    );
    expect(find.text('2026-09-06 13:04'), findsOneWidget);
  });
}
