import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_node/theme/ansible_design.dart';
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(body),
      ),
      findsOneWidget,
    );
    expect(find.text('私人'), findsOneWidget);
    expect(find.text('由 0 個 murmur 編成'), findsOneWidget);
    expect(find.text('尚未連結 murmur 來源。'), findsOneWidget);

    final bodyText = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(body),
      ),
    );
    // Assert against the design tokens rather than literals: the point is that
    // the note body rides the reading size and the back link rides the nav
    // size, so a deliberate retune of the scale does not read as a regression.
    expect(
      (bodyText.text as TextSpan).style?.fontSize,
      AnsibleDesign.readingTextSize,
    );
    expect(
      tester.widget<Text>(find.text('← 草地')).style?.fontSize,
      AnsibleDesign.navTextSize,
    );
  });
}
