import 'package:ansible_node/screens/inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inbox shows empty state instead of mock rows', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InboxScreen()));

    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('目前沒有收信'), findsOneWidget);
    expect(find.text('kr.'), findsNothing);
    expect(find.text('林下'), findsNothing);
    expect(find.text('週四讀書會'), findsNothing);
    expect(find.text('iPad mini'), findsNothing);
    expect(find.textContaining('patches'), findsNothing);
  });
}
