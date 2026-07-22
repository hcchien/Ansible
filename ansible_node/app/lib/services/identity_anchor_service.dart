import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_did/ansible_did.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'recovery_readiness_store.dart';
import 'canonical_identity_store.dart';
import 'relay_anchor_client.dart';
import 'secure_device_key_store.dart';

/// Signs anchor bodies / attestations with the IDENTITY (content) key.
///
/// Exposes both the identity public key hex (the anchor's `identity_key`) and a
/// signer over canonical bytes. Implementations: [SecureStorageIdentityKey]
/// (production, backed by `flutter_secure_storage`) and a test double.
///
/// Standard Ed25519 throughout, so signatures verify on the relay regardless of
/// whether they were produced via the rust signer or the pure-Dart
/// [Ed25519Keys] used here.
abstract class IdentityKey {
  const IdentityKey();
  /// The Ed25519 public key hex (the anchor's `identity_key`).
  Future<String> publicKeyHex();

  /// Signs [message] bytes with the identity key. Hex Ed25519 signature.
  Future<String> sign(List<int> message);

  Future<String> algorithm() async => 'ed25519';
  Future<CustodyClass> custodyClass() async => CustodyClass.software;
}

class ActiveIdentityKey implements IdentityKey {
  const ActiveIdentityKey({
    this.identityStore = const SecureCanonicalIdentityStore(),
  });

  final CanonicalIdentityStore identityStore;

  Future<CanonicalIdentity> _identity() async =>
      await identityStore.load() ??
      (throw StateError('Canonical identity not found.'));

  @override
  Future<String> publicKeyHex() async => (await _identity()).publicKeyHex;

  @override
  Future<String> sign(List<int> message) async =>
      (await DidSignerImpl().sign(message)).hex;

  @override
  Future<String> algorithm() async => (await _identity()).signingAlgorithm;

  @override
  Future<CustodyClass> custodyClass() async =>
      (await _identity()).custody == 'hardware'
      ? CustodyClass.hardware
      : CustodyClass.software;
}

/// Identity key backed by the same `ansible_did_private_key` secure-storage
/// entry the rest of the app uses. Derives the public key from the stored seed
/// and signs with [Ed25519Keys] (standard Ed25519).
class SecureStorageIdentityKey extends IdentityKey {
  final FlutterSecureStorage _storage;

  const SecureStorageIdentityKey({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String identityPrivateKeyStorageKey = 'ansible_did_private_key';

  Future<String> _privateKeyHex() async {
    final hex = await _storage.read(key: identityPrivateKeyStorageKey);
    if (hex == null) {
      throw StateError('No identity key in secure storage.');
    }
    return hex;
  }

  @override
  Future<String> publicKeyHex() async {
    return Ed25519Keys.publicKeyHexFromSeed(await _privateKeyHex());
  }

  @override
  Future<String> sign(List<int> message) async {
    return Ed25519Keys.sign(await _privateKeyHex(), message);
  }
}

/// In-memory [IdentityKey] for tests (and the recovery flow, which constructs
/// one from the just-decrypted private key).
class InMemoryIdentityKey extends IdentityKey {
  final String privateKeyHex;
  String? _publicKeyHex;

  InMemoryIdentityKey(this.privateKeyHex);

  @override
  Future<String> publicKeyHex() async {
    return _publicKeyHex ??= await Ed25519Keys.publicKeyHexFromSeed(
      privateKeyHex,
    );
  }

  @override
  Future<String> sign(List<int> message) async {
    return Ed25519Keys.sign(privateKeyHex, message);
  }
}

/// Outcome of a recovery (restore-from-backup) re-anchor.
class RecoveryResult {
  final IdentityAnchor anchor;
  final AnchorSubmitResult relayResult;
  final DeviceKey deviceKey;

  const RecoveryResult({
    required this.anchor,
    required this.relayResult,
    required this.deviceKey,
  });
}

/// Orchestrates the identity-anchor flows on the app side (recovery design
/// Tasks 3 + 5): build the device record + anchor, sign with the identity key,
/// persist the chain locally, and submit to the relay.
///
/// Constitution must-haves enforced here: device private keys never leave the
/// device / never in backups (the device key store is secure-storage only);
/// restore is opt-in + passphrase-gated (the caller decrypts the backup first);
/// recovery readiness stays user-visible (updated on success).
class IdentityAnchorService {
  final RelayAnchorClient relayClient;
  final IdentityAnchorRepository anchorRepository;
  final DeviceKeyStore deviceKeyStore;
  final RecoveryReadinessStore readinessStore;
  final DateTime Function() now;

  IdentityAnchorService({
    required this.relayClient,
    required this.anchorRepository,
    DeviceKeyStore? deviceKeyStore,
    RecoveryReadinessStore? readinessStore,
    DateTime Function()? now,
  }) : deviceKeyStore = deviceKeyStore ?? const SecureDeviceKeyStore(),
       readinessStore =
           readinessStore ?? const SharedPreferencesRecoveryReadinessStore(),
       now = now ?? (() => DateTime.now().toUtc());

  /// Builds and publishes the genesis (`reason: initial`) anchor for [did]:
  /// generates this device's software device key (if absent), has the identity
  /// key attest it, signs the canonical body, persists the chain locally, and
  /// POSTs to the relay (expects 201/active).
  Future<AnchorSubmitResult> publishInitialAnchor({
    required String did,
    required String handle,
    required IdentityKey identityKey,
  }) async {
    final identityKeyHex = await identityKey.publicKeyHex();
    final identityAlgorithm = await identityKey.algorithm();
    final identityCustody = await identityKey.custodyClass();
    final deviceKey = await _ensureDeviceKey();
    final enrolledAt = now();

    final deviceRecord = await _attestDevice(
      deviceKey: deviceKey,
      identityKey: identityKey,
      enrolledAt: enrolledAt,
    );

    final anchor = await _signAnchor(
      identityKey: identityKey,
      identityKeyHex: identityKeyHex,
      identityKeyAlgorithm: identityAlgorithm,
      identityCustody: identityCustody,
      did: did,
      handle: handle,
      alsoKnownAs: identityAlgorithm == 'ed25519'
          ? buildAlsoKnownAs(handle: handle, identityKeyHex: identityKeyHex)
          : ['at://$handle'],
      devices: [deviceRecord],
      prevAnchorCid: null,
      reason: AnchorReason.initial,
      createdAt: enrolledAt,
    );

    await anchorRepository.append(did, anchor);
    final result = await relayClient.submitAnchor(anchor);
    return result;
  }

  /// The recovery wizard's restore-from-backup path (recovery design Task 5,
  /// flow 1 collapse): the recovered identity key signs the new anchor as BOTH
  /// the new `sig` and the `device_sig` (possession of the identity key is full
  /// authority → immediate `rotation`, per the relay contract).
  ///
  /// Caller supplies [identityKey] reconstructed from the just-decrypted backup
  /// (e.g. `InMemoryIdentityKey(decryptedPrivateKeyHex)`) and the existing
  /// active anchor fetched from the relay ([previous]) to chain against. A
  /// FRESH device key is generated for this device and attested by the
  /// recovered identity key.
  ///
  /// On a relay 200 the new anchor is persisted locally and recovery readiness
  /// is refreshed.
  Future<RecoveryResult> recoverFromBackupRotation({
    required String did,
    required String handle,
    required IdentityKey identityKey,
    required IdentityAnchor previous,
  }) async {
    final identityKeyHex = await identityKey.publicKeyHex();
    final enrolledAt = now();

    // A fresh device key for THIS device (the lost device's key is gone — it
    // was never backed up, by design).
    final deviceKey = await DeviceKey.generate();

    final deviceRecord = await _attestDevice(
      deviceKey: deviceKey,
      identityKey: identityKey,
      enrolledAt: enrolledAt,
    );

    final anchor = await _signRotationAnchor(
      identityKey: identityKey,
      identityKeyHex: identityKeyHex,
      did: did,
      handle: handle,
      // Preserve the existing alias set across rotation (e.g. a bridged
      // did:plc); fall back to the canonical handle + did:key binding.
      alsoKnownAs: previous.alsoKnownAs.isNotEmpty
          ? previous.alsoKnownAs
          : buildAlsoKnownAs(handle: handle, identityKeyHex: identityKeyHex),
      devices: [deviceRecord],
      prevAnchorCid: previous.computeCid(),
      createdAt: enrolledAt,
    );

    final result = await relayClient.submitAnchor(anchor);

    // Only persist + flip readiness once the relay accepts (200 active).
    if (result.state == AnchorState.active) {
      // Reset any stale local chain (this device "lost" the identity), then
      // seed it with the previous active anchor so the local chain is sound,
      // and append the new rotation anchor.
      await anchorRepository.deleteAll(did);
      await anchorRepository.append(did, previous);
      await anchorRepository.append(did, anchor);
      await deviceKeyStore.save(deviceKey);
      await readinessStore.markBackupCreated(at: enrolledAt);
    }

    return RecoveryResult(
      anchor: anchor,
      relayResult: result,
      deviceKey: deviceKey,
    );
  }

  Future<DeviceKey> _ensureDeviceKey() async {
    final existing = await deviceKeyStore.load();
    if (existing != null) return existing;
    final generated = await DeviceKey.generate();
    await deviceKeyStore.save(generated);
    return generated;
  }

  Future<AnchorDeviceRecord> _attestDevice({
    required DeviceKey deviceKey,
    required IdentityKey identityKey,
    required DateTime enrolledAt,
  }) async {
    final attestationMessage = deviceKey.deviceAttestationMessage(
      custodyClass: CustodyClass.software,
      enrolledAt: enrolledAt,
    );
    final attestationSig = await identityKey.sign(attestationMessage);
    return deviceKey.toDeviceRecord(
      custodyClass: CustodyClass.software,
      enrolledAt: enrolledAt,
      attestationSigHex: attestationSig,
    );
  }

  Future<IdentityAnchor> _signAnchor({
    required IdentityKey identityKey,
    required String identityKeyHex,
    String identityKeyAlgorithm = 'ed25519',
    CustodyClass identityCustody = CustodyClass.software,
    required String did,
    required String handle,
    required List<String> alsoKnownAs,
    required List<AnchorDeviceRecord> devices,
    required String? prevAnchorCid,
    required AnchorReason reason,
    required DateTime createdAt,
    String? deviceSig,
  }) async {
    // Build an unsigned anchor first to compute the canonical body, then sign.
    final unsigned = IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      identityKeyAlgorithm: identityKeyAlgorithm,
      alsoKnownAs: alsoKnownAs,
      custodyClass: identityCustody,
      devices: devices,
      prevAnchorCid: prevAnchorCid,
      reason: reason,
      createdAt: createdAt,
      sig: '',
    );
    final body = utf8.encode(unsigned.canonicalBodyJson());
    final sig = await identityKey.sign(body);
    return IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      identityKeyAlgorithm: identityKeyAlgorithm,
      alsoKnownAs: alsoKnownAs,
      custodyClass: identityCustody,
      devices: devices,
      prevAnchorCid: prevAnchorCid,
      reason: reason,
      createdAt: createdAt,
      sig: sig,
      deviceSig: deviceSig,
    );
  }

  /// Rotation anchor where the recovered identity key signs BOTH `sig` (as the
  /// new key) and `device_sig` (which the relay verifies against the PRIOR
  /// active identity key — here the same key, since recovery-by-backup
  /// reinstates the same identity key).
  Future<IdentityAnchor> _signRotationAnchor({
    required IdentityKey identityKey,
    required String identityKeyHex,
    required String did,
    required String handle,
    required List<String> alsoKnownAs,
    required List<AnchorDeviceRecord> devices,
    required String? prevAnchorCid,
    required DateTime createdAt,
  }) async {
    final unsigned = IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      alsoKnownAs: alsoKnownAs,
      custodyClass: CustodyClass.software,
      devices: devices,
      prevAnchorCid: prevAnchorCid,
      reason: AnchorReason.rotation,
      createdAt: createdAt,
      sig: '',
    );
    final body = utf8.encode(unsigned.canonicalBodyJson());
    // Same key signs twice (new-key sig + prior-key device_sig). The relay
    // verifies `sig` against the new identity_key and `device_sig` against the
    // previous active anchor's identity_key — equal here.
    final sig = await identityKey.sign(body);
    return IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      alsoKnownAs: alsoKnownAs,
      custodyClass: CustodyClass.software,
      devices: devices,
      prevAnchorCid: prevAnchorCid,
      reason: AnchorReason.rotation,
      createdAt: createdAt,
      sig: sig,
      deviceSig: sig,
    );
  }
}
