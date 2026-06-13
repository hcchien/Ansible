import 'dart:convert';

import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/recovery_readiness_store.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

/// A tiny in-process "relay" that verifies the same things the real
/// AnchorStore does (canonical CID, identity-key sig, device attestations) so
/// the walkthrough exercises the real contract, not a rubber stamp.
class _FakeRelay {
  final Map<String, IdentityAnchor> active = {};

  RelayAnchorClient client() {
    return RelayAnchorClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          final did = Uri.decodeComponent(request.url.pathSegments.last);
          final anchor = active[did];
          if (anchor == null) {
            return http.Response(jsonEncode({'error': 'anchor_not_found'}), 404);
          }
          final wire = anchor.toCanonicalMap()
            ..['anchor_cid'] = anchor.computeCid()
            ..['state'] = 'active';
          return http.Response(jsonEncode(wire), 200);
        }
        // POST submit.
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final recoveryProof = body.remove('recovery_proof') as String?;
        final anchor = IdentityAnchor.fromMap(body);

        // Verify device attestations against the anchor's identity key.
        for (final device in anchor.devices) {
          final ok = await DeviceKey.verifyAttestation(
            identityKeyHex: anchor.identityKey,
            deviceId: device.deviceId,
            deviceKeyHex: device.deviceKey,
            custodyClass: device.custodyClass,
            enrolledAt: device.enrolledAt,
            attestationSigHex: device.attestationSig,
          );
          if (!ok) {
            return http.Response(
              jsonEncode({'error': 'invalid_attestation'}),
              401,
            );
          }
        }

        // Verify the body sig against identity_key.
        final sigOk = await _verify(
          anchor.identityKey,
          utf8.encode(anchor.canonicalBodyJson()),
          anchor.sig,
        );
        if (!sigOk) {
          return http.Response(jsonEncode({'error': 'invalid_signature'}), 401);
        }

        final reason = body['reason'] as String;
        if (reason == 'rotation') {
          final prev = active[anchor.did];
          if (prev == null || anchor.prevAnchorCid != prev.computeCid()) {
            return http.Response(jsonEncode({'error': 'chain_mismatch'}), 409);
          }
          // device_sig must verify against the PRIOR identity key.
          final deviceSigOk = await _verify(
            prev.identityKey,
            utf8.encode(anchor.canonicalBodyJson()),
            body['device_sig'] as String,
          );
          if (!deviceSigOk) {
            return http.Response(
              jsonEncode({'error': 'invalid_signature'}),
              401,
            );
          }
        }
        if (reason == 'recovery') {
          final prev = active[anchor.did];
          final ok = prev != null &&
              recoveryProof != null &&
              await _enrolledDeviceSigned(prev, anchor, recoveryProof);
          if (!ok) {
            return http.Response(
              jsonEncode({'error': 'invalid_recovery_proof'}),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'state': 'pending',
              'anchor_cid': anchor.computeCid(),
              'grace_until': '2026-06-16T00:00:00Z',
            }),
            202,
          );
        }

        active[anchor.did] = anchor;
        return http.Response(
          jsonEncode({'state': 'active', 'anchor_cid': anchor.computeCid()}),
          reason == 'initial' ? 201 : 200,
        );
      }),
    );
  }

  Future<bool> _enrolledDeviceSigned(
    IdentityAnchor prev,
    IdentityAnchor anchor,
    String sig,
  ) async {
    for (final d in prev.devices) {
      if (await _verify(
        d.deviceKey,
        utf8.encode(anchor.canonicalBodyJson()),
        sig,
      )) {
        return true;
      }
    }
    return false;
  }
}

Future<bool> _verify(String pubHex, List<int> message, String sigHex) {
  return Ed25519Keys.verify(
    publicKeyHex: pubHex,
    message: message,
    sigHex: sigHex,
  );
}

void main() {
  test('publishInitialAnchor builds + signs + persists + posts (201)',
      () async {
    final relay = _FakeRelay();
    final repo = InMemoryIdentityAnchorRepository();
    final service = IdentityAnchorService(
      relayClient: relay.client(),
      anchorRepository: repo,
      deviceKeyStore: InMemoryDeviceKeyStore(),
      readinessStore: InMemoryRecoveryReadinessStore(),
      now: () => DateTime.utc(2026, 6, 13),
    );
    final identityKey = await _newIdentityKey();

    final result = await service.publishInitialAnchor(
      did: 'did:plc:alice',
      handle: 'alice.elix.cool',
      identityKey: identityKey,
    );

    expect(result.statusCode, 201);
    expect(result.state, AnchorState.active);

    final latest = await repo.latest('did:plc:alice');
    expect(latest, isNotNull);
    expect(latest!.reason, AnchorReason.initial);
    expect(latest.devices, hasLength(1));
    expect(latest.devices.first.custodyClass, CustodyClass.software);
    // The chain verifies structurally.
    final verification = await repo.verifyChain('did:plc:alice');
    expect(verification.isValid, isTrue);
  });

  // ── DEVICE-LOSS WALKTHROUGH (Phase 1 exit criterion) ──────────────────────
  //
  // Seeds an account with an identity key + initial anchor, "loses" the device
  // (clears secure storage: identity key + device key gone), then restores from
  // a backup blob + passphrase and re-anchors via the rotation flow against a
  // relay returning 200 — asserting the identity key is recovered and a NEW
  // device record is enrolled.
  test('device-loss walkthrough: backup restore re-anchors via rotation',
      () async {
    final relay = _FakeRelay();
    final readiness = InMemoryRecoveryReadinessStore();

    // --- Device A: enrol the account ---
    final deviceAStore = InMemoryDeviceKeyStore();
    final repoA = InMemoryIdentityAnchorRepository();
    final identityKey = await _newIdentityKey();
    final identityPrivateKeyHex = (identityKey as InMemoryIdentityKey)
        .privateKeyHex;

    final serviceA = IdentityAnchorService(
      relayClient: relay.client(),
      anchorRepository: repoA,
      deviceKeyStore: deviceAStore,
      readinessStore: readiness,
      now: () => DateTime.utc(2026, 6, 1),
    );
    await serviceA.publishInitialAnchor(
      did: 'did:plc:alice',
      handle: 'alice.elix.cool',
      identityKey: identityKey,
    );
    final originalDeviceId = (await deviceAStore.load())!.deviceId;

    // The user backs up the identity key under a passphrase (D5-b).
    final backupBlob = await IdentityKeyBackup.encrypt(
      passphrase: 'correct horse battery staple',
      identityPrivateKeyHex: identityPrivateKeyHex,
      did: 'did:plc:alice',
    );

    // --- DEVICE LOSS: fresh device, empty secure storage ---
    final deviceBStore = InMemoryDeviceKeyStore();
    final repoB = InMemoryIdentityAnchorRepository();
    String? recoveredKeyInSecureStorage; // stands in for secure storage write.

    expect(await deviceBStore.load(), isNull);

    final serviceB = IdentityAnchorService(
      relayClient: relay.client(),
      anchorRepository: repoB,
      deviceKeyStore: deviceBStore,
      readinessStore: readiness,
      now: () => DateTime.utc(2026, 6, 13),
    );

    // --- Restore from backup + passphrase ---
    final decryptedKeyHex = await IdentityKeyBackup.decrypt(
      passphrase: 'correct horse battery staple',
      blobJson: backupBlob,
    );
    expect(decryptedKeyHex, identityPrivateKeyHex); // key is recovered.
    recoveredKeyInSecureStorage = decryptedKeyHex; // "install" into storage.

    final recoveredIdentityKey = InMemoryIdentityKey(decryptedKeyHex);
    final previous =
        await serviceB.relayClient.fetchActiveAnchor('did:plc:alice');
    expect(previous, isNotNull);

    final result = await serviceB.recoverFromBackupRotation(
      did: 'did:plc:alice',
      handle: previous!.handle,
      identityKey: recoveredIdentityKey,
      previous: previous,
    );

    // The relay accepted the rotation (200 active).
    expect(result.relayResult.statusCode, 200);
    expect(result.relayResult.state, AnchorState.active);

    // The identity key is recovered (same key, same public key).
    expect(recoveredKeyInSecureStorage, identityPrivateKeyHex);
    expect(
      await recoveredIdentityKey.publicKeyHex(),
      await identityKey.publicKeyHex(),
    );

    // A NEW device record was enrolled — distinct from the lost device.
    final newDevice = await deviceBStore.load();
    expect(newDevice, isNotNull);
    expect(newDevice!.deviceId, isNot(originalDeviceId));
    expect(result.anchor.devices, hasLength(1));
    expect(result.anchor.devices.first.deviceId, newDevice.deviceId);
    expect(result.anchor.reason, AnchorReason.rotation);

    // Local chain is sound: initial → rotation.
    final chain = await repoB.list('did:plc:alice');
    expect(chain, hasLength(2));
    expect(chain.first.reason, AnchorReason.initial);
    expect(chain.last.reason, AnchorReason.rotation);
    expect((await repoB.verifyChain('did:plc:alice')).isValid, isTrue);

    // Recovery readiness is refreshed.
    expect(await readiness.hasBackup(), isTrue);
  });

  test('recoverFromBackupRotation does NOT persist on relay rejection',
      () async {
    final relay = _FakeRelay();
    final deviceStore = InMemoryDeviceKeyStore();
    final repo = InMemoryIdentityAnchorRepository();
    final identityKey = await _newIdentityKey();

    final service = IdentityAnchorService(
      relayClient: relay.client(),
      anchorRepository: repo,
      deviceKeyStore: deviceStore,
      readinessStore: InMemoryRecoveryReadinessStore(),
    );
    await service.publishInitialAnchor(
      did: 'did:plc:alice',
      handle: 'alice.elix.cool',
      identityKey: identityKey,
    );
    final previous =
        await service.relayClient.fetchActiveAnchor('did:plc:alice');

    // A DIFFERENT identity key cannot rotate (device_sig won't verify against
    // the prior key) → relay 401.
    final wrongKey = await _newIdentityKey();
    expect(
      () => service.recoverFromBackupRotation(
        did: 'did:plc:alice',
        handle: previous!.handle,
        identityKey: wrongKey,
        previous: previous,
      ),
      throwsA(isA<RelayAnchorException>()),
    );
  });
}

Future<IdentityKey> _newIdentityKey() async {
  return InMemoryIdentityKey(await Ed25519Keys.generateSeedHex());
}
