import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceKey', () {
    test('generates a software Ed25519 keypair with a device id', () async {
      final key = await DeviceKey.generate();
      expect(key.deviceId, isNotEmpty);
      expect(key.publicKeyHex.length, 64); // 32 bytes hex
      expect(key.privateKeyHex.length, 64); // 32-byte Ed25519 seed hex
      expect(key.publicKeyHex, isNot(key.privateKeyHex));
    });

    test('fromStored round-trips and can sign verifiably', () async {
      final key = await DeviceKey.generate();
      final restored = DeviceKey.fromStored(
        deviceId: key.deviceId,
        publicKeyHex: key.publicKeyHex,
        privateKeyHex: key.privateKeyHex,
      );
      final message = utf8.encode('hello device');
      final sigHex = await restored.sign(message);

      // Verify with the cryptography verifier against the public key.
      final ed = Ed25519();
      final pub = SimplePublicKey(
        _unhex(key.publicKeyHex),
        type: KeyPairType.ed25519,
      );
      final ok = await ed.verify(
        message,
        signature: Signature(_unhex(sigHex), publicKey: pub),
      );
      expect(ok, isTrue);
    });

    test('attestation message matches the relay device-attestation key order',
        () async {
      final key = DeviceKey.fromStored(
        deviceId: 'dev-1',
        publicKeyHex: 'aa' * 32,
        privateKeyHex: 'bb' * 32,
      );
      final enrolledAt = DateTime.utc(2026, 6, 13, 12);
      final message = key.deviceAttestationMessage(
        custodyClass: CustodyClass.software,
        enrolledAt: enrolledAt,
      );
      // The relay (@device_attestation_keys) signs exactly this byte string.
      final expected = '{"device_id":"dev-1","device_key":"${'aa' * 32}",'
          '"custody_class":"software",'
          '"enrolled_at":"${enrolledAt.toIso8601String()}"}';
      expect(utf8.decode(message), expected);
    });

    test(
      'attestation_sig verifies against the identity key over the canonical '
      'device record (device-key attestation walkthrough)',
      () async {
        // A separate identity key (the "content key").
        final ed = Ed25519();
        final identityKeyPair = await ed.newKeyPair();
        final identityPub = await identityKeyPair.extractPublicKey();
        final identityKeyHex = _hex(identityPub.bytes);

        final device = await DeviceKey.generate();
        final enrolledAt = DateTime.utc(2026, 6, 13);

        // The identity key signs the canonical device-record bytes.
        final message = device.deviceAttestationMessage(
          custodyClass: CustodyClass.software,
          enrolledAt: enrolledAt,
        );
        final attestation = await ed.sign(message, keyPair: identityKeyPair);
        final attestationSigHex = _hex(attestation.bytes);

        // Build the record and confirm the attestation verifies — this is the
        // exact check the relay's verify_device_attestations performs.
        final record = device.toDeviceRecord(
          custodyClass: CustodyClass.software,
          enrolledAt: enrolledAt,
          attestationSigHex: attestationSigHex,
        );
        expect(record.deviceKey, device.publicKeyHex);

        final ok = await DeviceKey.verifyAttestation(
          identityKeyHex: identityKeyHex,
          deviceId: record.deviceId,
          deviceKeyHex: record.deviceKey,
          custodyClass: record.custodyClass,
          enrolledAt: record.enrolledAt,
          attestationSigHex: record.attestationSig,
        );
        expect(ok, isTrue);

        // A tampered device key fails attestation.
        final bad = await DeviceKey.verifyAttestation(
          identityKeyHex: identityKeyHex,
          deviceId: record.deviceId,
          deviceKeyHex: 'cc' * 32,
          custodyClass: record.custodyClass,
          enrolledAt: record.enrolledAt,
          attestationSigHex: record.attestationSig,
        );
        expect(bad, isFalse);
      },
    );

    test('InMemoryDeviceKeyStore persists and clears', () async {
      final store = InMemoryDeviceKeyStore();
      expect(await store.load(), isNull);
      final key = await DeviceKey.generate();
      await store.save(key);
      expect((await store.load())!.deviceId, key.deviceId);
      await store.clear();
      expect(await store.load(), isNull);
    });
  });
}

List<int> _unhex(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
