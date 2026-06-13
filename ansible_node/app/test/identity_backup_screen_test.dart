import 'package:ansible_node/screens/identity_backup_screen.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/recovery_readiness_store.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 64-byte Ed25519 private key (hex). Not a real key.
const _keyHex =
    '9d61b19deff3a5b0ba849d0064cb8a4128b6a0c0d3c1b2e7f8a9b0c1d2e3f40'
    '5162738495a6b7c8d9e0f1a2b3c4d5e6f70819202122232425262728292a2b';

void main() {
  testWidgets(
    'backup screen produces an encrypted blob from a passphrase',
    (tester) async {
      final store = InMemoryRecoveryReadinessStore();
      String? seenPassphrase;
      String? seenKey;
      // Inject a fast fake encrypt: the real PBKDF2 path uses real Timers that
      // do not cooperate with the widget-test fake clock. The real crypto
      // round-trip is covered by store/test/identity_key_backup_test.dart; here
      // we verify the screen wiring (passphrase -> blob shown -> readiness set).
      await tester.pumpWidget(
        MaterialApp(
          home: IdentityBackupScreen(
            did: 'did:plc:alice',
            identityPrivateKeyHex: () async => _keyHex,
            readinessStore: store,
            encryptBackup: ({
              required String passphrase,
              required String identityPrivateKeyHex,
              String? did,
            }) async {
              seenPassphrase = passphrase;
              seenKey = identityPrivateKeyHex;
              return '{"type":"io.trisaura.identity.key_backup","did":"$did"}';
            },
          ),
        ),
      );
      await tester.pump();

      // zh-Hant copy (test locale falls back to zh-Hant).
      expect(find.text('建立加密備份'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('backup_passphrase_field')),
        'correct horse battery staple',
      );
      await tester.enterText(
        find.byKey(const Key('backup_passphrase_confirm_field')),
        'correct horse battery staple',
      );
      await tester.tap(find.byKey(const Key('backup_create_button')));
      await tester.pumpAndSettle();

      // The screen fed the typed passphrase + the identity key to the encryptor.
      expect(seenPassphrase, 'correct horse battery staple');
      expect(seenKey, _keyHex);

      // A blob is shown and the opt-in readiness flag was set.
      expect(find.byKey(const Key('backup_blob_box')), findsOneWidget);
      expect(await store.hasBackup(), isTrue);
    },
  );

  testWidgets('backup screen rejects mismatched passphrases', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityBackupScreen(
          did: 'did:plc:alice',
          identityPrivateKeyHex: () async => _keyHex,
          readinessStore: InMemoryRecoveryReadinessStore(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('backup_passphrase_field')),
      'one',
    );
    await tester.enterText(
      find.byKey(const Key('backup_passphrase_confirm_field')),
      'two',
    );
    await tester.tap(find.byKey(const Key('backup_create_button')));
    await tester.pump();

    expect(find.byKey(const Key('backup_error_text')), findsOneWidget);
    expect(find.byKey(const Key('backup_blob_box')), findsNothing);
  });

  testWidgets(
    'settings shows ⚠ 尚未備份 when no backup exists',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsHomeScreen(
            db: db,
            did: 'did:plc:abcdefghijklmnop',
            recoveryReadinessStore: InMemoryRecoveryReadinessStore(),
            identityPrivateKeyProvider: () async => _keyHex,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_recovery_row')),
        find.byType(ListView),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();

      expect(find.text('⚠ 尚未備份'), findsOneWidget);
      expect(find.text('可復原：已備份'), findsNothing);
    },
  );

  testWidgets(
    'settings shows 可復原：已備份 when a backup exists',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsHomeScreen(
            db: db,
            did: 'did:plc:abcdefghijklmnop',
            recoveryReadinessStore: InMemoryRecoveryReadinessStore(
              backupAt: DateTime.utc(2026, 6, 1),
            ),
            identityPrivateKeyProvider: () async => _keyHex,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_recovery_row')),
        find.byType(ListView),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();

      expect(find.text('可復原：已備份'), findsOneWidget);
      expect(find.text('⚠ 尚未備份'), findsNothing);
    },
  );
}
