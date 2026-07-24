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

    expect(find.text('SYSTEM MESSAGE · 系統訊息'), findsOneWidget);
    expect(find.text('下面這些內容會離開你的裝置，傳送給遠端 AI 做整理。'), findsOneWidget);
    expect(find.text('PRIVATE · LOCAL SOURCE'), findsOneWidget);
    expect(accepted, isFalse);

    await tester.enterText(
      find.byKey(const Key('transformation_body_field')),
      'Edited body',
    );
    await tester.tap(find.text('送出 · 約 14 字'));
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
    expect(find.text('儲存為私人筆記'), findsOneWidget);
    expect(saved, isFalse);

    await tester.tap(find.text('儲存為私人筆記'));
    await tester.pumpAndSettle();

    expect(saved, isTrue);
  });
}
