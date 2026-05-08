import 'package:ansible_node/widgets/summary_review_sheet.dart';
import 'package:ansible_node/widgets/transformation_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('transformation review waits for explicit accept', (
    tester,
  ) async {
    var accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransformationReviewSheet(
            title: 'Draft note',
            body: 'Generated body',
            sourceLabels: const ['murmur-1'],
            containsPrivateSource: true,
            onAccept: (title, body) async {
              accepted = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('轉換審閱'), findsOneWidget);
    expect(find.text('Private/local source'), findsOneWidget);
    expect(accepted, isFalse);

    await tester.enterText(
      find.byKey(const Key('transformation_body_field')),
      'Edited body',
    );
    await tester.tap(find.text('接受'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
  });

  testWidgets('summary review can save result as private note', (tester) async {
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SummaryReviewSheet(
            summary: 'Short discussion summary',
            sourceLabels: const ['discussion-1'],
            onSaveAsNote: (summary) async {
              saved = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('摘要審閱'), findsOneWidget);
    expect(find.text('Save as private note'), findsOneWidget);
    expect(saved, isFalse);

    await tester.tap(find.text('Save as private note'));
    await tester.pumpAndSettle();

    expect(saved, isTrue);
  });
}
