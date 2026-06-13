import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity_anchor.dart';

/// Per-install SOFTWARE device key (recovery design Task 3, D1 v1.1).
///
/// A device key is a software Ed25519 keypair generated on-device and stored in
/// platform secure storage. Constitution must-have: the device PRIVATE key
/// NEVER leaves the device and is NEVER included in any backup — the
/// "a physical enrolled device acted" property comes from this no-backup
/// policy, not from hardware. `custody_class` is recorded as `software`; a
/// future hardware upgrade hooks in here with zero protocol change.
///
/// This is pure-Dart (the `cryptography` package, already a store dependency)
/// so it is testable under `dart test`. The app binds the
/// [DeviceKeyStore] to `flutter_secure_storage`.
///
/// The device record's `attestation_sig` is produced by the IDENTITY key
/// signing the canonical device-record bytes (minus `attestation_sig`). Those
/// bytes are produced by [deviceAttestationMessage] / [attestationMessageFor],
/// which match the relay's `AnsibleRelay.Identity.AnchorStore`
/// `@device_attestation_keys` (`device_id, device_key, custody_class,
/// enrolled_at`) byte-for-byte: the leading keys of [AnchorDeviceRecord]'s
/// canonical map, in the same insertion order, JSON with no whitespace.
class DeviceKey {
  /// Stable per-install device id (UUID, opaque). Not secret.
  final String deviceId;

  /// Ed25519 public key, hex-encoded.
  final String publicKeyHex;

  /// Ed25519 private key, hex-encoded. NEVER backed up; lives only in secure
  /// storage. Held in memory only as long as needed to sign.
  final String privateKeyHex;

  const DeviceKey({
    required this.deviceId,
    required this.publicKeyHex,
    required this.privateKeyHex,
  });

  static final Ed25519 _ed25519 = Ed25519();

  /// Generates a fresh software Ed25519 device keypair with a random
  /// [deviceId]. Pure-Dart; no native deps.
  static Future<DeviceKey> generate({String? deviceId}) async {
    final keyPair = await _ed25519.newKeyPair();
    final priv = await keyPair.extractPrivateKeyBytes();
    final pub = await keyPair.extractPublicKey();
    return DeviceKey(
      deviceId: deviceId ?? _randomId(),
      publicKeyHex: _hex(pub.bytes),
      privateKeyHex: _hex(priv),
    );
  }

  /// Reconstructs a [DeviceKey] from stored hex (e.g. read from secure
  /// storage). The private key hex is the 32-byte Ed25519 seed.
  factory DeviceKey.fromStored({
    required String deviceId,
    required String publicKeyHex,
    required String privateKeyHex,
  }) {
    return DeviceKey(
      deviceId: deviceId,
      publicKeyHex: publicKeyHex,
      privateKeyHex: privateKeyHex,
    );
  }

  /// Signs [message] with this device's private key. Hex-encoded Ed25519
  /// signature. Used for device co-signatures / vetoes — NOT for attestation
  /// (which the identity key produces).
  Future<String> sign(List<int> message) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(_unhex(privateKeyHex));
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return _hex(signature.bytes);
  }

  /// The canonical bytes the identity key signs to attest THIS device key — the
  /// device record minus `attestation_sig`, fixed key order, no whitespace.
  ///
  /// Matches the relay `AnchorStore.device_attestation_message/1`
  /// (`@device_attestation_keys = device_id, device_key, custody_class,
  /// enrolled_at`).
  List<int> deviceAttestationMessage({
    required CustodyClass custodyClass,
    required DateTime enrolledAt,
  }) {
    return attestationMessageFor(
      deviceId: deviceId,
      deviceKeyHex: publicKeyHex,
      custodyClass: custodyClass,
      enrolledAt: enrolledAt,
    );
  }

  /// Builds the full [AnchorDeviceRecord] once the identity key has produced
  /// [attestationSigHex] over [deviceAttestationMessage].
  AnchorDeviceRecord toDeviceRecord({
    required CustodyClass custodyClass,
    required DateTime enrolledAt,
    required String attestationSigHex,
  }) {
    return AnchorDeviceRecord(
      deviceId: deviceId,
      deviceKey: publicKeyHex,
      custodyClass: custodyClass,
      enrolledAt: enrolledAt.toUtc(),
      attestationSig: attestationSigHex,
    );
  }

  /// Verifies that [attestationSigHex] is a valid Ed25519 signature by
  /// [identityKeyHex] over the canonical device-record bytes. Used by tests and
  /// (optionally) defensive client-side checks before publishing.
  static Future<bool> verifyAttestation({
    required String identityKeyHex,
    required String deviceId,
    required String deviceKeyHex,
    required CustodyClass custodyClass,
    required DateTime enrolledAt,
    required String attestationSigHex,
  }) async {
    final message = attestationMessageFor(
      deviceId: deviceId,
      deviceKeyHex: deviceKeyHex,
      custodyClass: custodyClass,
      enrolledAt: enrolledAt,
    );
    final publicKey = SimplePublicKey(
      _unhex(identityKeyHex),
      type: KeyPairType.ed25519,
    );
    return _ed25519.verify(
      message,
      signature: Signature(_unhex(attestationSigHex), publicKey: publicKey),
    );
  }

  /// The canonical attestation message (UTF-8 bytes) for arbitrary device-record
  /// fields. Field order and encoding mirror the relay's
  /// `@device_attestation_keys`.
  static List<int> attestationMessageFor({
    required String deviceId,
    required String deviceKeyHex,
    required CustodyClass custodyClass,
    required DateTime enrolledAt,
  }) {
    // Insertion order is significant — must match the relay and the leading
    // keys of AnchorDeviceRecord.toCanonicalMap.
    final body = <String, Object?>{
      'device_id': deviceId,
      'device_key': deviceKeyHex,
      'custody_class': custodyClass.storageValue,
      'enrolled_at': enrolledAt.toUtc().toIso8601String(),
    };
    return utf8.encode(jsonEncode(body));
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _randomId() {
    // Random 16-byte opaque id, hex. Avoids a uuid dep here (kept pure).
    final bytes = SecretKeyData.random(length: 16).bytes;
    return _hex(bytes);
  }
}

/// Pure-Dart Ed25519 helpers shared by the device key and the identity-key
/// recovery flow. Standard Ed25519 (interchangeable with the rust signer the
/// rest of the app uses) so signatures produced here verify on the relay.
class Ed25519Keys {
  const Ed25519Keys._();

  static final Ed25519 _ed25519 = Ed25519();

  /// Derives the Ed25519 public key hex from a private-key hex. Accepts either a
  /// 32-byte seed or a 64-byte expanded secret (seed || public key, the
  /// libsodium/rust format) — only the leading 32-byte seed is used. Used after
  /// a backup restore to recover the identity public key from the decrypted
  /// private key.
  static Future<String> publicKeyHexFromSeed(String privateKeyHex) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(_seed(privateKeyHex));
    final pub = await keyPair.extractPublicKey();
    return _hex(pub.bytes);
  }

  /// Signs [message] with [privateKeyHex] (seed or 64-byte expanded secret);
  /// hex Ed25519 signature.
  static Future<String> sign(String privateKeyHex, List<int> message) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(_seed(privateKeyHex));
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return _hex(signature.bytes);
  }

  /// Verifies [sigHex] is a valid Ed25519 signature by [publicKeyHex] over
  /// [message]. (Convenience for tests / defensive checks.)
  static Future<bool> verify({
    required String publicKeyHex,
    required List<int> message,
    required String sigHex,
  }) async {
    final pub = SimplePublicKey(_unhex(publicKeyHex), type: KeyPairType.ed25519);
    return _ed25519.verify(
      message,
      signature: Signature(_unhex(sigHex), publicKey: pub),
    );
  }

  /// Generates a fresh random 32-byte Ed25519 seed (hex). Pure-Dart.
  static Future<String> generateSeedHex() async {
    final keyPair = await _ed25519.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    return _hex(seed);
  }

  /// The 32-byte Ed25519 seed from a private-key hex (handling the 64-byte
  /// expanded format).
  static Uint8List _seed(String privateKeyHex) {
    final bytes = _unhex(privateKeyHex);
    if (bytes.length == 32) return bytes;
    if (bytes.length == 64) return Uint8List.sublistView(bytes, 0, 32);
    throw ArgumentError.value(
      privateKeyHex,
      'privateKeyHex',
      'Ed25519 private key hex must be 32 or 64 bytes',
    );
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

/// Persists the local device key. The PRIVATE key lives ONLY here (platform
/// secure storage in the app); it is never backed up or synced.
abstract class DeviceKeyStore {
  /// Loads the persisted device key, or null if none has been generated.
  Future<DeviceKey?> load();

  /// Persists [key] (overwriting any existing one).
  Future<void> save(DeviceKey key);

  /// Removes the persisted device key (e.g. identity reset / device wipe).
  Future<void> clear();
}

/// In-memory [DeviceKeyStore] for tests / pure-Dart use.
class InMemoryDeviceKeyStore implements DeviceKeyStore {
  DeviceKey? _key;

  InMemoryDeviceKeyStore([this._key]);

  @override
  Future<DeviceKey?> load() async => _key;

  @override
  Future<void> save(DeviceKey key) async => _key = key;

  @override
  Future<void> clear() async => _key = null;
}
