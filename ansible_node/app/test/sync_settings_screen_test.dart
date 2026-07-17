import 'package:ansible_node/screens/sync_settings_screen.dart';
import 'package:ansible_node/services/app_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public publish errors are reported without throwing sync', () async {
    final summary = await bestEffortPublicPublish(
      () async =>
          throw StateError('Relay publication failed: 401 unverified_did'),
    );

    expect(summary.failed, 1);
    expect(summary.errorMessage, contains('Relay publication failed'));
  });

  testWidgets('sync settings shows empty circle state instead of mock board', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: SyncSettingsScreen(db: db, localDid: 'did:elix:test'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('SYNC'), findsOneWidget);
    expect(find.text('目前沒有同步的圈'), findsOneWidget);
    expect(find.text('週四讀書會'), findsNothing);
    expect(find.textContaining('讀書會'), findsNothing);
  });

  testWidgets('sync settings presents Elix Relay and hides Nostr by default', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: SyncSettingsScreen(db: db, localDid: 'did:elix:test'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Elix Relay'), findsOneWidget);
    expect(find.text('新增 Elix Relay'), findsOneWidget);
    expect(find.byKey(const Key('nostr_relay_url_field')), findsNothing);

    await tester.tap(find.text('Nostr Relay'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nostr_relay_url_field')), findsOneWidget);
  });

  testWidgets('sync settings can prefill discovered Elix Relay URL', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: SyncSettingsScreen(
          db: db,
          localDid: 'did:elix:test',
          initialForumHostUrl: 'https://relay.example',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            widget.controller.text == 'https://relay.example',
      ),
      findsOneWidget,
    );
  });

  test('hostComplianceNeedsWarning gates only positive declarations', () {
    expect(hostComplianceNeedsWarning('constitution_compliant'), isFalse);
    expect(hostComplianceNeedsWarning('compatible'), isFalse);
    expect(hostComplianceNeedsWarning('unknown'), isTrue);
    expect(hostComplianceNeedsWarning('non_compliant'), isTrue);
    expect(hostComplianceNeedsWarning(null), isTrue);
    // Fail closed on unrecognised future levels.
    expect(hostComplianceNeedsWarning('something_new'), isTrue);
  });

  group('host compliance warning on add', () {
    Future<AppDatabase> pumpAndSubmitAddHost(
      WidgetTester tester, {
      required Future<String?> Function(String url) complianceFetcher,
    }) async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      await tester.pumpWidget(
        MaterialApp(
          home: SyncSettingsScreen(
            db: db,
            localDid: 'did:elix:test',
            complianceFetcher: complianceFetcher,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('新增 Elix Relay'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Example Host');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'https://host.example',
      );
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      return db;
    }

    testWidgets('an undeclared host warns and cancel aborts the add', (
      tester,
    ) async {
      final db = await pumpAndSubmitAddHost(
        tester,
        complianceFetcher: (_) async => null,
      );

      expect(
        find.byKey(const Key('host_compliance_warning_dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('此主機未聲明符合憲章'), findsOneWidget);

      await tester.tap(find.byKey(const Key('host_compliance_cancel')));
      await tester.pumpAndSettle();

      expect(await DriftRemoteNodeRepository(db).list(), isEmpty);
    });

    testWidgets('add anyway saves the host with its compliance level', (
      tester,
    ) async {
      final db = await pumpAndSubmitAddHost(
        tester,
        complianceFetcher: (_) async => 'unknown',
      );

      expect(
        find.byKey(const Key('host_compliance_warning_dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('host_compliance_add_anyway')));
      await tester.pumpAndSettle();

      final nodes = await DriftRemoteNodeRepository(db).list();
      expect(nodes, hasLength(1));
      expect(nodes.single.url, 'https://host.example');
      expect(nodes.single.constitutionCompliance, 'unknown');
    });

    testWidgets('a non-compliant host gets the stronger warning copy', (
      tester,
    ) async {
      await pumpAndSubmitAddHost(
        tester,
        complianceFetcher: (_) async => 'non_compliant',
      );

      expect(
        find.byKey(const Key('host_compliance_warning_dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('此主機聲明不符合憲章'), findsOneWidget);
    });

    testWidgets('a compliant host adds silently as before', (tester) async {
      final db = await pumpAndSubmitAddHost(
        tester,
        complianceFetcher: (_) async => 'constitution_compliant',
      );

      expect(
        find.byKey(const Key('host_compliance_warning_dialog')),
        findsNothing,
      );
      final nodes = await DriftRemoteNodeRepository(db).list();
      expect(nodes, hasLength(1));
      expect(nodes.single.constitutionCompliance, 'constitution_compliant');
    });
  });
}
