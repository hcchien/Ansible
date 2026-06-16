import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('phone navigation opens composers and enforces murmur limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'elix_board_swipe_shown': true});

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('今天有什麼想記下的？'), findsNothing);
    await tester.tap(find.byKey(const Key('home_compose_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Murmur'));
    await tester.pumpAndSettle();

    expect(find.text('Murmur'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('訂閱'), findsNothing);

    expect(find.text('MURMUR'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
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
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('測試碎念存檔'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_compose_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note_title_field')), findsOneWidget);
    expect(find.byKey(const Key('note_body_field')), findsOneWidget);
    expect(find.text('新增筆記'), findsNothing);

    await tester.tap(find.byKey(const Key('note_editor_cancel_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet'), findsNothing);
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
    String pdsEndpoint = 'https://elix.cool',
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
