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
    tester.view.physicalSize = const Size(390, 844);
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

    expect(find.text('Murmur'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Discussions'), findsOneWidget);
    expect(find.text('訂閱'), findsNothing);

    await tester.tap(find.text('Murmur'));
    await tester.pumpAndSettle();

    expect(find.text('捕捉 Murmur'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('murmur_body_field')),
      'a' * 501,
    );
    await tester.pump();
    expect(find.text('500 / 500'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Linked murmurs'), findsOneWidget);

    await tester.tap(find.text('Discussions'));
    await tester.pumpAndSettle();
    expect(find.text('AI 摘要'), findsOneWidget);
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
