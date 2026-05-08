import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('note workspace creates note with title and body', (
    tester,
  ) async {
    final repository = InMemoryContentItemRepository();
    var reloadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            authorDid: 'did:plc:alice',
            contentItemRepository: repository,
            onContentItemsChanged: () async {
              reloadCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note_title_field')),
      'Field notes',
    );
    await tester.enterText(
      find.byKey(const Key('note_body_field')),
      'A note needs a body.',
    );
    await tester.tap(find.text('建立'));
    await tester.pumpAndSettle();

    final notes = await repository.list(mode: ContentMode.note);
    expect(notes.single.authorDid, 'did:plc:alice');
    expect(notes.single.title, 'Field notes');
    expect(notes.single.body, 'A note needs a body.');
    expect(notes.single.visibility, ContentVisibility.private);
    expect(notes.single.localOnly, isTrue);
    expect(reloadCount, 1);
  });

  testWidgets('note creation requires title and body', (tester) async {
    final repository = InMemoryContentItemRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            authorDid: 'did:plc:alice',
            contentItemRepository: repository,
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('建立'));
    await tester.pumpAndSettle();

    expect(find.text('請輸入標題'), findsOneWidget);
    expect(find.text('請輸入內文'), findsOneWidget);
    expect(await repository.list(mode: ContentMode.note), isEmpty);
  });
}
