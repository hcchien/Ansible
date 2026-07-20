import 'package:ansible_node/screens/search_screen.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search screen queries SQLite and opens a local board', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 7, 20);
    await DriftBoardRepository(db).create(
      Board(
        id: 'offline-board',
        slug: 'offline',
        title: '離線搜尋看板',
        description: '完全來自本機 SQLite',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(db: db, localDid: 'did:elix:local'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SQLite');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('離線搜尋看板'), findsOneWidget);
    expect(find.textContaining('完全來自本機 SQLite'), findsOneWidget);

    await tester.tap(find.text('離線搜尋看板'));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadsListScreen), findsOneWidget);
  });
}
