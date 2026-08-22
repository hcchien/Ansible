import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'atproto_client.dart';
import 'canonical_identity_store.dart';
import 'relay_identity_client.dart';

/// Safely upgrades a legacy exportable Ed25519 identity to a non-exportable
/// platform-backed P-256 key (iOS, Android, or macOS) without changing the
/// account DID.
class HardwareKeyUpgradeService {
  HardwareKeyUpgradeService({
    HardwareIdentityKey? hardwareKey,
    DidSigner? legacySigner,
    AtProtoClient? atProtoClient,
    RelayIdentityClient? identityClient,
    CanonicalIdentityStore? identityStore,
    FlutterSecureStorage? secureStorage,
  }) : _hardwareKey = hardwareKey ?? HardwareIdentityKey(),
       _legacySigner = legacySigner ?? DidSignerImpl(),
       _atProtoClient = atProtoClient ?? AtProtoClient(),
       _identityClient = identityClient ?? RelayIdentityClient(),
       _identityStore = identityStore ?? const SecureCanonicalIdentityStore(),
       _storage = secureStorage ?? const FlutterSecureStorage();

  final HardwareIdentityKey _hardwareKey;
  final DidSigner _legacySigner;
  final AtProtoClient _atProtoClient;
  final RelayIdentityClient _identityClient;
  final CanonicalIdentityStore _identityStore;
  final FlutterSecureStorage _storage;

  Future<CanonicalIdentity> upgrade() async {
    final identity = await _identityStore.load();
    if (identity == null) throw StateError('Canonical identity not found.');
    if (identity.signingAlgorithm == IdentityKeyAlgorithm.p256Sha256.wireName) {
      return identity;
    }

    final current = await _identityClient.fetchVerificationKey(identity.did);
    if (current == null) throw StateError('Relay identity not found.');
    if (current.publicKeyHex.toLowerCase() !=
        identity.publicKeyHex.toLowerCase()) {
      throw StateError('Relay identity key does not match this device.');
    }

    final hardware = await _hardwareKey.generate();
    if (hardware.custody != IdentityKeyCustody.hardware) {
      throw StateError(
        'This device did not provide hardware-backed identity key custody.',
      );
    }
    final issuedAt = DateTime.now().toUtc().toIso8601String();
    final unsigned = <String, Object?>{
      'did': identity.did,
      'expected_key_version': current.keyVersion,
      'issued_at': issuedAt,
      'new_custody': 'hardware',
      'new_public_key_hex': hardware.publicKeyHex,
      'new_signing_algorithm': hardware.algorithm.wireName,
      'type': 'io.trisaura.identity.keyRotation',
      'version': 1,
    };
    final payload = utf8.encode(jsonEncode(unsigned));
    final oldSignature = await _legacySigner.sign(payload);
    final newSignature = await _hardwareKey.sign(payload);

    final result = await _atProtoClient.rotateIdentityKey({
      ...unsigned,
      'old_signature': oldSignature.hex,
      'new_signature': newSignature.hex,
    });
    if (result.publicKeyHex.toLowerCase() !=
        hardware.publicKeyHex.toLowerCase()) {
      throw StateError('Relay confirmed a different rotation key.');
    }

    final upgraded = CanonicalIdentity(
      did: identity.did,
      handle: identity.handle,
      publicKeyHex: hardware.publicKeyHex,
      signingAlgorithm: hardware.algorithm.wireName,
      custody: IdentityKeyCustody.hardware.wireName,
      genesisCommitment: identity.genesisCommitment,
      legacyDids: identity.legacyDids,
    );
    await _identityStore.save(upgraded);
    await _storage.write(
      key: 'ansible_identity_signing_algorithm',
      value: hardware.algorithm.wireName,
    );
    await _storage.write(
      key: 'ansible_identity_custody',
      value: IdentityKeyCustody.hardware.wireName,
    );
    return upgraded;
  }
}
