import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first AI action opens setup then returns to original action', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          initialBoard: HomeBoard.personal,
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const Key('home_ai_button')));
    await tester.pumpAndSettle();

    expect(find.text('AI 提供者設定'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.byKey(const Key('ai_base_url_field')), findsOneWidget);
    expect(find.byKey(const Key('ai_model_field')), findsOneWidget);
    expect(find.byKey(const Key('ai_api_key_field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai_model_field')),
      'manual-review',
    );
    await tester.tap(find.text('測試連線'));
    await tester.pumpAndSettle();
    expect(find.text('連線測試通過'), findsOneWidget);

    await tester.tap(find.text('儲存並繼續'));
    await tester.pumpAndSettle();

    expect(find.text('AI · 從你的 murmur 找'), findsOneWidget);
    expect(find.text('不會用來訓練。不會離開這台手機。'), findsOneWidget);
  });
}
