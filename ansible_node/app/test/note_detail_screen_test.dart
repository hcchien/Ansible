import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping a note opens its detail page', (tester) async {
    const body =
        'This is the full note body. It should be readable on the single note page, not only as a listing preview.';
    final note = ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Field notes',
      body: body,
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 8, 10, 30),
      updatedAt: DateTime.utc(2026, 5, 8, 11, 45),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteWorkspaceScreen(notes: [note])),
      ),
    );

    await tester.tap(find.text('Field notes'));
    await tester.pumpAndSettle();

    expect(find.text('NOTE · 始於 2026.05.08'), findsOneWidget);
    expect(find.text('Field notes'), findsOneWidget);
    expect(find.text(body), findsOneWidget);
    expect(find.text('PRIVATE'), findsOneWidget);
    expect(find.text('由 0 個 murmur 編成'), findsOneWidget);
    expect(find.text('尚未連結 murmur 來源。'), findsOneWidget);
  });
}
