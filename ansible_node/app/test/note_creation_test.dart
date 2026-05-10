import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_node/widgets/note_markdown_text.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('note markdown body renders toolbar formatting styles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoteMarkdownBody('## Heading\n**Bold** _italic_ <u>line</u>'),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final root = richText.text as TextSpan;
    final spans = root.children!.whereType<TextSpan>().toList();

    expect(
      spans.any(
        (span) =>
            span.text == 'Heading' && span.style?.fontWeight == FontWeight.w600,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.text == 'Bold' && span.style?.fontWeight == FontWeight.w700,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.text == 'italic' && span.style?.fontStyle == FontStyle.italic,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.text == 'line' &&
            span.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
  });

  testWidgets(
    'note markdown editor hides source syntax while styling content',
    (tester) async {
      final controller = NoteMarkdownEditingController(text: '**Bold**');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(),
        withComposing: false,
      );
      final spans = span.children!.whereType<TextSpan>().toList();

      expect(controller.text, '**Bold**');
      expect(span.toPlainText(), 'Bold');
      expect(
        spans.any(
          (child) =>
              child.text == 'Bold' &&
              child.style?.fontWeight == FontWeight.w700,
        ),
        isTrue,
      );
    },
  );

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
    expect(find.text('編輯中 · EDITING'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(
      find.byKey(const Key('note_title_field')),
      'Field notes',
    );
    await tester.enterText(
      find.byKey(const Key('note_body_field')),
      'A note needs a body.',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final notes = await repository.list(mode: ContentMode.note);
    expect(notes.single.authorDid, 'did:plc:alice');
    expect(notes.single.title, 'Field notes');
    expect(notes.single.body, 'A note needs a body.');
    expect(notes.single.visibility, ContentVisibility.private);
    expect(notes.single.localOnly, isTrue);
    expect(reloadCount, 1);
  });

  testWidgets('note workspace creates public note from editor visibility', (
    tester,
  ) async {
    final repository = InMemoryContentItemRepository();
    final published =
        <({ContentItem item, DistributionPreference preference})>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            authorDid: 'did:plc:alice',
            contentItemRepository: repository,
            onPublishContentItem: (item, preference) async {
              published.add((item: item, preference: preference));
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note_editor_visibility_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公開'));
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note_title_field')),
      'Public field notes',
    );
    await tester.enterText(
      find.byKey(const Key('note_body_field')),
      'Visible to the federation adapters.',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final notes = await repository.list(mode: ContentMode.note);
    expect(notes.single.visibility, ContentVisibility.public);
    expect(notes.single.localOnly, isFalse);
    expect(notes.single.publishedAt, isNotNull);
    expect(published.single.item.id, notes.single.id);
    expect(
      published.single.preference,
      DistributionPreference.nostrAndActivityPub,
    );
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
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('請輸入標題'), findsOneWidget);
    expect(find.text('請輸入內文'), findsOneWidget);
    expect(await repository.list(mode: ContentMode.note), isEmpty);
  });

  testWidgets(
    'note editor format toolbar appears only for selected body text',
    (tester) async {
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
      await tester.enterText(find.byKey(const Key('note_body_field')), '正文');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note_format_bold')), findsNothing);

      final bodyField = tester.widget<TextField>(
        find.byKey(const Key('note_body_field')),
      );
      bodyField.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note_format_bold')), findsOneWidget);

      await tester.tap(find.byKey(const Key('note_format_bold')));
      await tester.pumpAndSettle();

      final formattedBodyField = tester.widget<TextField>(
        find.byKey(const Key('note_body_field')),
      );
      expect(formattedBodyField.controller?.text, '**正文**');
      expect(
        formattedBodyField.controller
            ?.buildTextSpan(
              context: tester.element(find.byKey(const Key('note_body_field'))),
              style: const TextStyle(),
              withComposing: false,
            )
            .toPlainText(),
        '正文',
      );
    },
  );

  testWidgets('note editor can drag a murmur into the body', (tester) async {
    final repository = InMemoryContentItemRepository();
    final now = DateTime.utc(2026, 5, 9, 10);
    final murmur = ContentItem(
      id: 'murmur-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.murmur,
      body: '松茸喜歡的是被擾動過、卻沒被毀掉的林子。',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            authorDid: 'did:plc:alice',
            murmurs: [murmur],
            contentItemRepository: repository,
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('note_editor_murmur_card_murmur-1'));
    final body = find.byKey(const Key('note_body_drop_target'));
    await tester.dragFrom(
      tester.getCenter(card),
      tester.getCenter(body) - tester.getCenter(card),
    );
    await tester.pumpAndSettle();

    final bodyField = tester.widget<TextField>(
      find.byKey(const Key('note_body_field')),
    );
    expect(bodyField.controller?.text, contains('> 松茸喜歡的是被擾動過、卻沒被毀掉的林子。'));
  });

  testWidgets('note editor title remains editable after toolbar interaction', (
    tester,
  ) async {
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
    await tester.enterText(find.byKey(const Key('note_body_field')), '正文');
    final bodyField = tester.widget<TextField>(
      find.byKey(const Key('note_body_field')),
    );
    bodyField.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 2,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note_format_italic')));
    await tester.tap(find.byKey(const Key('note_title_field')));
    await tester.enterText(find.byKey(const Key('note_title_field')), '可輸入標題');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final notes = await repository.list(mode: ContentMode.note);
    expect(notes.single.title, '可輸入標題');
    expect(notes.single.body, '_正文_');
  });

  testWidgets('note workspace edits an existing note title and body', (
    tester,
  ) async {
    final repository = InMemoryContentItemRepository();
    final now = DateTime.utc(2026, 5, 9, 11);
    final note = ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Original title',
      body: 'Original body',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
    );
    await repository.create(note);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            authorDid: 'did:plc:alice',
            notes: [note],
            contentItemRepository: repository,
            onPublishContentItem: (item, preference) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Original title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note_title_field')),
      'Updated title',
    );
    await tester.enterText(
      find.byKey(const Key('note_body_field')),
      'Updated body',
    );
    await tester.tap(find.byKey(const Key('note_editor_visibility_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公開'));
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final updated = await repository.getById('note-1');
    expect(updated?.title, 'Updated title');
    expect(updated?.body, 'Updated body');
    expect(updated?.visibility, ContentVisibility.public);
    expect(updated?.localOnly, isFalse);
  });

  testWidgets('note workspace sort toggle changes listing order', (
    tester,
  ) async {
    final older = ContentItem(
      id: 'note-old',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Older note',
      body: 'First',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 8, 10),
      updatedAt: DateTime.utc(2026, 5, 8, 10),
    );
    final newer = ContentItem(
      id: 'note-new',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Newer note',
      body: 'Second',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 9, 10),
      updatedAt: DateTime.utc(2026, 5, 9, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteWorkspaceScreen(
            authorDid: 'did:plc:alice',
            notes: [older, newer],
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Newer note')).dy,
      lessThan(tester.getTopLeft(find.text('Older note')).dy),
    );

    await tester.tap(find.byKey(const Key('note_sort_toggle')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Older note')).dy,
      lessThan(tester.getTopLeft(find.text('Newer note')).dy),
    );
  });
}
