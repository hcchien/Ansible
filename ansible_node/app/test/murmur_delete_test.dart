import 'package:ansible_node/screens/murmur_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('murmur row swipe delete removes an unused murmur', (
    tester,
  ) async {
    _setTallViewport(tester);
    final repository = InMemoryContentItemRepository();
    final murmur = _murmur(id: 'murmur-1', body: '不必修復的鬆動感');
    await repository.create(murmur);
    var reloadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MurmurScreen(
            authorDid: 'did:plc:alice',
            contentItemRepository: repository,
            recentMurmurs: [murmur],
            onSaved: () async {
              reloadCount += 1;
            },
          ),
        ),
      ),
    );

    final row = find.byKey(const Key('murmur_row_murmur-1')).last;
    await tester.scrollUntilVisible(
      row,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(row, const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(find.text('把這條 murmur 拔掉？'), findsOneWidget);
    expect(find.text('還沒被任何 note 用過。刪掉之後不留痕跡。'), findsOneWidget);

    await tester.tap(find.text('刪除').last);
    await tester.pumpAndSettle();

    expect(await repository.list(mode: ContentMode.murmur), isEmpty);
    expect(reloadCount, 1);
  });

  testWidgets('referenced murmur deletion asks for a second confirmation', (
    tester,
  ) async {
    _setTallViewport(tester);
    final repository = InMemoryContentItemRepository();
    final murmur = _murmur(id: 'murmur-1', body: '松茸喜歡的是被擾動過的林子');
    await repository.create(murmur);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MurmurScreen(
            authorDid: 'did:plc:alice',
            contentItemRepository: repository,
            recentMurmurs: [murmur],
            murmurReferenceCounts: const {'murmur-1': 1},
          ),
        ),
      ),
    );

    final row = find.byKey(const Key('murmur_row_murmur-1')).last;
    await tester.scrollUntilVisible(
      row,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(row, const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(find.text('這條 murmur 已經被 1 篇 note 引用。'), findsOneWidget);

    await tester.tap(find.text('刪除').last);
    await tester.pumpAndSettle();
    expect(find.text('確定要讓引用斷開？'), findsOneWidget);

    await tester.tap(find.text('仍然刪除'));
    await tester.pumpAndSettle();

    expect(await repository.list(mode: ContentMode.murmur), isEmpty);
  });
}

void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ContentItem _murmur({required String id, required String body}) {
  return ContentItem(
    id: id,
    authorDid: 'did:plc:alice',
    mode: ContentMode.murmur,
    body: body,
    status: ContentStatus.active,
    visibility: ContentVisibility.private,
    createdAt: DateTime.utc(2026, 5, 9, 10),
    updatedAt: DateTime.utc(2026, 5, 9, 10),
  );
}
