import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone navigation exposes content modes and murmur limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('碎念'), findsOneWidget);
    expect(find.text('筆記'), findsOneWidget);
    expect(find.text('討論'), findsOneWidget);
    expect(find.text('訂閱'), findsNothing);

    await tester.tap(find.text('碎念'));
    await tester.pumpAndSettle();

    expect(find.text('MURMUR · 碎念'), findsOneWidget);
    expect(find.text('送出'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('murmur_body_field')),
      'a' * 501,
    );
    await tester.pump();
    expect(find.text('500 / 500'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('murmur_body_field')),
      '測試碎念存檔',
    );
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();
    expect(find.text('已送出'), findsOneWidget);
    expect(find.text('測試碎念存檔'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.text('測試碎念存檔'));
    await tester.pumpAndSettle();
    expect(find.text('MURMUR'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('刪除碎念'), findsOneWidget);

    await tester.tap(find.text('刪除碎念'));
    await tester.pumpAndSettle();
    expect(find.text('刪除碎念？'), findsOneWidget);

    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(find.text('測試碎念存檔'), findsNothing);
    expect(find.text('送出的碎念會先留在這裡。'), findsOneWidget);

    await tester.tap(find.text('筆記'));
    await tester.pumpAndSettle();
    expect(find.text('草地'), findsOneWidget);
    expect(find.text('散落'), findsOneWidget);
    expect(find.text('測試碎念存檔'), findsNothing);
    expect(find.text('還沒有散落的碎念。'), findsOneWidget);
    expect(find.text('來源 · LINEAGE'), findsOneWidget);

    await tester.tap(find.text('討論'));
    await tester.pumpAndSettle();
    expect(find.text('AI 摘要'), findsOneWidget);
    expect(find.text('討論串'), findsOneWidget);
  });
}

class _EmptyDidManager implements DidManager {
  @override
  Future<OwnedDid> generate() {
    throw UnimplementedError('Not used by this test.');
  }

  @override
  Future<OwnedDid?> load() async => null;

  @override
  Future<void> delete() async {}
}

class _ExistingDidPlcManager implements DidPlcManager {
  @override
  Future<DidPlcResult> createDid({
    required String handle,
    String pdsEndpoint = 'https://trisaura.io',
    String? signingKeyHex,
  }) {
    throw UnimplementedError('Not used by this test.');
  }

  @override
  Future<void> deleteDid() async {}

  @override
  Future<DidPlcResult?> loadDid() async => const DidPlcResult(
    did: 'did:plc:abcdefghijklmnop',
    genesisJson: '{"type":"plc_genesis"}',
    publicKeyHex: 'ab',
  );
}
