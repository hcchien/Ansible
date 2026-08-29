import 'dart:async';
import 'package:ansible_node/services/canonical_identity_store.dart';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/app_locale_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accepted_terms_store.dart';

void main() {
  testWidgets('terms gate appears before registration and existing login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _EmptyDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('accept_terms_checkbox')), findsOneWidget);
    expect(
      find.text('Create identity first,\nthen join the community.'),
      findsNothing,
    );

    await db.close();
    db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      MyApp(
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const Key('accept_terms_checkbox')), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('renders identity anchor screen when no DID is persisted', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        termsAcceptanceStore: const AcceptedTermsStore(),
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _EmptyDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
      ),
    );
    await tester.pump();

    // First run now opens on the onboarding intro; skip through to the
    // identity-creation (passkey) screen.
    expect(find.text('Enter'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Elix'), findsOneWidget);
    expect(
      find.text('Create identity first,\nthen join the community.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'You control your account and content · protected by device keys',
      ),
      findsOneWidget,
    );
  });

  testWidgets('review build exposes credential-free public-content access', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        termsAcceptanceStore: const AcceptedTermsStore(),
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _EmptyDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
        googlePlayReviewAccessEnabled: true,
      ),
    );
    await tester.pump();

    final access = find.byKey(const Key('google_play_review_public_content'));
    expect(access, findsOneWidget);
    await tester.tap(access);
    await tester.pumpAndSettle();

    expect(find.text('Google Play review access'), findsOneWidget);
    expect(find.text('Elix public content'), findsOneWidget);
  });

  testWidgets('uses swipe shell navigation on phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'elix_board_swipe_shown': true});

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        termsAcceptanceStore: const AcceptedTermsStore(),
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
        initialBoard: HomeBoard.personal,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const Key('board_swipe_page_view')), findsOneWidget);
    expect(find.byKey(const Key('screen_style_button')), findsNothing);
    expect(find.byKey(const Key('settings_button')), findsOneWidget);
    // 個人版 moved out of the bottom bar into 我/Settings; 時間軸 + 討論區 remain
    // the two on-bar board affordances.
    expect(find.byKey(const Key('board_switch_personal')), findsNothing);
    expect(find.byKey(const Key('board_switch_timeline')), findsOneWidget);
    expect(find.byKey(const Key('board_switch_forum')), findsOneWidget);
    expect(find.text('PAPER · LIGHT'), findsNothing);
    expect(find.text('INK · DARK'), findsNothing);
    expect(find.text('No entries yet'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    final securityRow = find.byKey(const Key('settings_identity_security_row'));
    final settingsScroll = find.descendant(
      of: find.byType(SettingsHomeScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      securityRow,
      300,
      scrollable: settingsScroll,
    );
    expect(securityRow, findsOneWidget);
    expect(find.text('清除身份 (Clear Identity)'), findsNothing);
  });

  testWidgets(
    'swipe shell controls do not overflow on phone width in English',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'elix_board_swipe_shown': true});

      final db = AppDatabase(NativeDatabase.memory());
      final localeController = AppLocaleController(
        store: InMemoryAppLocalePreferenceStore(),
      );
      addTearDown(() => db.close());
      await localeController.setPreference(AppLocalePreference.en);

      await tester.pumpWidget(
        MyApp(
          termsAcceptanceStore: const AcceptedTermsStore(),
          db: db,
          didManager: _EmptyDidManager(),
          didPlcManager: _ExistingDidPlcManager(),
          canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
          localeController: localeController,
          initialBoard: HomeBoard.personal,
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const Key('board_swipe_page_view')), findsOneWidget);
      expect(find.byKey(const Key('screen_style_button')), findsNothing);
      expect(find.byKey(const Key('settings_button')), findsOneWidget);
      expect(find.byKey(const Key('board_switch_personal')), findsNothing);
      expect(find.byKey(const Key('board_switch_timeline')), findsOneWidget);
      expect(find.byKey(const Key('board_switch_forum')), findsOneWidget);
    },
  );

  testWidgets('applies the app text size step globally', (tester) async {
    SharedPreferences.setMockInitialValues({
      'elix-reading-text-scale': 'large',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MyApp(
        termsAcceptanceStore: const AcceptedTermsStore(),
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
        initialBoard: HomeBoard.personal,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final context = tester.element(find.byType(HomeShell));
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(11.8, 0.01));
  });

  testWidgets('ignores MobileMoica callback links without web-session error', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final links = StreamController<Uri>.broadcast(sync: true);
    addTearDown(() async {
      await links.close();
      await db.close();
    });

    await tester.pumpWidget(
      MyApp(
        termsAcceptanceStore: const AcceptedTermsStore(),
        db: db,
        didManager: _EmptyDidManager(),
        didPlcManager: _ExistingDidPlcManager(),
        canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
        webSessionLinks: links.stream,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    links.add(
      Uri.parse('trisaura://mobilemoica/callback?error_code=ok&error_message='),
    );
    await tester.pump();

    expect(find.text('Invalid web session request.'), findsNothing);
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
  Future<void> deleteDid() async {}

  @override
  Future<DidPlcResult?> loadDid() async => null;
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
