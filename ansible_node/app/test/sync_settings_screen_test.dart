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

    await tester.pumpWidget(MaterialApp(home: SyncSettingsScreen(db: db)));
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

    await tester.pumpWidget(MaterialApp(home: SyncSettingsScreen(db: db)));
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
}
