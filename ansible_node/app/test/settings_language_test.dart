import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/app_locale_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accepted_terms_store.dart';

void main() {
  testWidgets('settings opens reading preferences and persists text size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsHomeScreen(db: db, did: 'did:plc:abcdefghijklmnop'),
      ),
    );
    await tester.pump();

    expect(find.text('鎖定'), findsNothing);

    await tester.dragUntilVisible(
      find.text('閱讀偏好'),
      find.byType(ListView),
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('閱讀偏好'));
    await tester.pumpAndSettle();

    expect(find.text('字級'), findsOneWidget);
    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('elix-reading-text-scale'), 'large');
  });

  testWidgets('settings blocked list shows local blocks and can unblock', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final now = DateTime.utc(2026, 5, 31, 8);
    await DriftContactRepository(db).upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:blockedperson',
        displayName: 'Blocked User',
        relationship: ContactRelationship.blocked,
        trustState: ContactTrustState.blocked,
        messengerAvailability: MessengerAvailability.blocked,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsHomeScreen(db: db, did: 'did:plc:abcdefghijklmnop'),
      ),
    );
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('封鎖名單'),
      find.byType(ListView),
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('封鎖名單'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked User'), findsOneWidget);
    await tester.tap(find.text('解除封鎖'));
    await tester.pumpAndSettle();

    final contact = await DriftContactRepository(
      db,
    ).contactForDid('did:plc:blockedperson');
    expect(contact!.relationship, ContactRelationship.unknown);
    expect(contact.trustState, ContactTrustState.unverified);
    expect(contact.messengerAvailability, MessengerAvailability.unresolved);
  });

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

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_language_row')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
    SharedPreferences.setMockInitialValues({'elix_board_swipe_shown': true});
    await localeController.setPreference(AppLocalePreference.en);

    await tester.pumpWidget(
      MyApp(
        termsAcceptanceStore: const AcceptedTermsStore(),
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
        localeController: localeController,
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const Key('board_swipe_page_view')), findsOneWidget);
    expect(find.byKey(const Key('settings_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    expect(find.text('Wallet'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_language_row')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

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
  Future<void> deleteDid() async {}

  @override
  Future<DidPlcResult?> loadDid() async => const DidPlcResult(
    did: 'did:plc:abcdefghijklmnop',
    genesisJson: '{"type":"plc_genesis"}',
    publicKeyHex: 'ab',
  );
}
