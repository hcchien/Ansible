import 'package:ansible_node/screens/murmur_detail_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('murmur detail does not show mock related notes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MurmurDetailScreen(
          murmur: ContentItem(
            id: 'murmur-1',
            authorDid: 'did:plc:alice',
            mode: ContentMode.murmur,
            body: 'A real murmur',
            status: ContentStatus.active,
            visibility: ContentVisibility.private,
            createdAt: DateTime.utc(2026, 5, 8),
            updatedAt: DateTime.utc(2026, 5, 8),
          ),
        ),
      ),
    );

    expect(find.text('A real murmur'), findsOneWidget);
    expect(find.text('廢墟中的協作'), findsNothing);
    expect(find.text('荒涼感作為一種介面語言'), findsNothing);
    expect(find.text('為什麼我們抗拒重建'), findsNothing);
    expect(find.text('我們在「廢墟」裡到底在尋找什麼？'), findsNothing);
    expect(find.text('0 個 note 引用了它'), findsNothing);
    expect(find.text('0 次被討論'), findsNothing);
  });
}
