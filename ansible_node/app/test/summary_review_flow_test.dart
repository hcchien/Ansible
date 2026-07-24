import 'package:ansible_node/screens/discussion_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('discussion summary action opens summary review', (tester) async {
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DiscussionDetailScreen(
          title: 'Discussion title',
          body: 'Discussion body',
          onSaveSummaryAsNote: (summary) async {
            saved = true;
          },
        ),
      ),
    );

    await tester.tap(find.text('AI 摘要'));
    await tester.pumpAndSettle();

    expect(find.text('摘要審閱'), findsOneWidget);
    expect(find.textContaining('Discussion title'), findsWidgets);

    await tester.tap(find.text('儲存為私人筆記'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });
}
