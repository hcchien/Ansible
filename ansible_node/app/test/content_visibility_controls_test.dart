import 'package:ansible_node/screens/murmur_screen.dart';
import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('murmur saves selected public visibility', (tester) async {
    final repository = InMemoryContentItemRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MurmurScreen(
            authorDid: 'did:plc:alice',
            contentItemRepository: repository,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('murmur_visibility_chip')));
    await tester.pumpAndSettle();
    expect(find.text('誰能看見 · VISIBILITY'), findsOneWidget);
    await tester.tap(find.text('公開'));
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('murmur_body_field')),
      'public murmur',
    );
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    final items = await repository.list(mode: ContentMode.murmur);
    expect(items.single.visibility, ContentVisibility.public);
    expect(items.single.localOnly, isFalse);
  });

  testWidgets('note workspace displays note visibility from content item', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            notes: [
              ContentItem(
                id: 'note-1',
                authorDid: 'did:plc:alice',
                mode: ContentMode.note,
                title: 'Public note',
                body: 'Visible to public',
                status: ContentStatus.active,
                visibility: ContentVisibility.public,
                createdAt: DateTime.utc(2026, 5, 8),
                updatedAt: DateTime.utc(2026, 5, 8),
                localOnly: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Public note'), findsOneWidget);
    expect(find.text('公開'), findsOneWidget);
    expect(find.text('私人'), findsNothing);
  });

  testWidgets('note workspace can update note visibility', (tester) async {
    final repository = InMemoryContentItemRepository();
    final note = ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Draft note',
      body: 'A private note',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 8),
      updatedAt: DateTime.utc(2026, 5, 8),
    );
    await repository.create(note);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            notes: [note],
            contentItemRepository: repository,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('visibility_chip_note-1')));
    await tester.pumpAndSettle();
    expect(find.text('誰能看見 · VISIBILITY'), findsOneWidget);
    await tester.tap(find.text('公開'));
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    final updated = await repository.getById('note-1');
    expect(updated!.visibility, ContentVisibility.public);
    expect(updated.localOnly, isFalse);
  });
}
