import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/services/app_locale_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders identity anchor screen when no DID is persisted', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _EmptyDidPlcManager(),
      ),
    );
    await tester.pump();

    expect(find.text('Elix'), findsOneWidget);
    expect(find.text('在這裡，\n先慢一點。'), findsOneWidget);
    expect(find.text('沒有帳號 · 沒有雲端 · 不會被收集'), findsOneWidget);
  });

  testWidgets('uses a single-column forum layout on phone width', (
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Discussion Area'), findsOneWidget);
    expect(find.text('Public · Open'), findsOneWidget);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Sign out of this device'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Sign out of this device'), findsOneWidget);
    expect(find.text('清除身份 (Clear Identity)'), findsNothing);
  });

  testWidgets('forum controls do not overflow on phone width in German', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    final localeController = AppLocaleController(
      store: InMemoryAppLocalePreferenceStore(),
    );
    addTearDown(() => db.close());
    await localeController.setPreference(AppLocalePreference.de);

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        localeController: localeController,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Diskussionsbereich'), findsOneWidget);
    expect(find.text('Noch keine Beiträge'), findsOneWidget);
    expect(find.text('Forum'), findsOneWidget);
    expect(find.text('AI Zusammenfassung'), findsOneWidget);
  });

  testWidgets('applies the app text size step globally', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final context = tester.element(find.byType(HomeShell));
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(10.8, 0.01));
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

class _EmptyDidPlcManager implements DidPlcManager {
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
  Future<DidPlcResult?> loadDid() async => null;
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
