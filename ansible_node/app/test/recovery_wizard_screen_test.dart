import 'dart:convert';

import 'package:ansible_node/screens/recovery_wizard_screen.dart';
import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/recovery_readiness_store.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

// A 32-byte Ed25519 seed hex (the recovered identity key). Not real.
const _keyHex =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';

// A pre-built backup blob naming did:plc:alice (parse only needs the envelope).
final _blob = jsonEncode({
  'type': IdentityKeyBackup.typeName,
  'format_version': IdentityKeyBackup.formatVersion,
  'kdf': IdentityKeyBackup.kdfPbkdf2,
  'cipher': IdentityKeyBackup.cipherAesGcm,
  'did': 'did:plc:alice',
  'salt': base64.encode(List<int>.filled(16, 1)),
  'nonce': base64.encode(List<int>.filled(12, 2)),
  'ciphertext': base64.encode(List<int>.filled(48, 3)),
  'mac': base64.encode(List<int>.filled(16, 4)),
});

IdentityAnchorService _service({required bool relaySucceeds}) {
  // The "previous" active anchor served by GET, with one enrolled device whose
  // attestation we don't re-verify here (the relay stub is permissive — the
  // real verification is covered by identity_anchor_service_test).
  final previous = IdentityAnchor(
    did: 'did:plc:alice',
    handle: 'alice.elix.cool',
    identityKey: 'ab' * 32,
    custodyClass: CustodyClass.software,
    devices: const [],
    reason: AnchorReason.initial,
    createdAt: DateTime.utc(2026, 6, 1),
    sig: 'cd' * 64,
  );

  final client = RelayAnchorClient(
    baseUrl: 'http://relay.local',
    client: MockClient((request) async {
      if (request.method == 'GET') {
        final wire = previous.toCanonicalMap()
          ..['anchor_cid'] = previous.computeCid()
          ..['state'] = 'active';
        return http.Response(jsonEncode(wire), 200);
      }
      if (relaySucceeds) {
        return http.Response(
          jsonEncode({'state': 'active', 'anchor_cid': 'sha256:new'}),
          200,
        );
      }
      return http.Response(jsonEncode({'error': 'invalid_signature'}), 401);
    }),
  );

  return IdentityAnchorService(
    relayClient: client,
    anchorRepository: InMemoryIdentityAnchorRepository(),
    deviceKeyStore: InMemoryDeviceKeyStore(),
    readinessStore: InMemoryRecoveryReadinessStore(),
    now: () => DateTime.utc(2026, 6, 13),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('wrong passphrase shows an error', (tester) async {
    await tester.pumpWidget(_wrap(RecoveryWizardScreen(
      service: _service(relaySucceeds: true),
      installRecoveredKey: (_) async {},
      // Fast fake decrypt that throws on the wrong passphrase.
      decryptBackup: ({required passphrase, required blobJson}) async {
        if (passphrase != 'right') {
          throw const BackupDecryptException('wrong');
        }
        return _keyHex;
      },
      identityKeyFactory: (hex) => InMemoryIdentityKey(hex),
    )));
    await tester.pump();

    // zh-Hant copy (test locale falls back to zh-Hant).
    expect(find.text('復原我的帳號'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recovery_blob_field')),
      _blob,
    );
    await tester.enterText(
      find.byKey(const Key('recovery_passphrase_field')),
      'nope',
    );
    await tester.tap(find.byKey(const Key('recovery_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_error_text')), findsOneWidget);
    expect(find.text('密語錯誤或備份已損毀。'), findsOneWidget);
    expect(find.byKey(const Key('recovery_success_text')), findsNothing);
  });

  testWidgets('correct passphrase + relay success shows recovered state',
      (tester) async {
    String? installedKey;
    String? recoveredDid;
    await tester.pumpWidget(_wrap(RecoveryWizardScreen(
      service: _service(relaySucceeds: true),
      installRecoveredKey: (hex) async => installedKey = hex,
      decryptBackup: ({required passphrase, required blobJson}) async => _keyHex,
      identityKeyFactory: (hex) => InMemoryIdentityKey(hex),
      onRecovered: (did) => recoveredDid = did,
    )));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('recovery_blob_field')),
      _blob,
    );
    await tester.enterText(
      find.byKey(const Key('recovery_passphrase_field')),
      'right',
    );
    await tester.tap(find.byKey(const Key('recovery_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_success_text')), findsOneWidget);
    expect(find.text('帳號已復原'), findsOneWidget);
    expect(installedKey, _keyHex);
    expect(recoveredDid, 'did:plc:alice');
  });
}
