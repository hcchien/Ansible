import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/app_locale_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings language picker changes app locale preference', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final localeController = AppLocaleController(
      store: InMemoryAppLocalePreferenceStore(),
    );
    addTearDown(() => db.close());
    await localeController.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsHomeScreen(
          db: db,
          did: 'did:plc:abcdefghijklmnop',
          localeController: localeController,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('語言'), findsOneWidget);
    expect(find.text('跟隨系統'), findsOneWidget);

    await tester.tap(find.text('語言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(localeController.preference, AppLocalePreference.en);
    expect(localeController.locale?.languageCode, 'en');
  });

  testWidgets('app applies selected locale to settings UI', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final localeController = AppLocaleController(
      store: InMemoryAppLocalePreferenceStore(),
    );
    addTearDown(() => db.close());
    await localeController.setPreference(AppLocalePreference.en);

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        localeController: localeController,
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Murmur'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Discussions'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
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
