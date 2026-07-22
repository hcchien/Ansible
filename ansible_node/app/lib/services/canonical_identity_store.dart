import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The persisted canonical identity of this device's account.
class CanonicalIdentity {
  /// The canonical `did:elix`.
  final String did;

  /// Full handle, e.g. `alice.elix.cool`.
  final String handle;

  /// Ed25519 identity public key, hex-encoded (the anchor `identity_key`).
  final String publicKeyHex;
  final String signingAlgorithm;
  final String custody;

  const CanonicalIdentity({
    required this.did,
    required this.handle,
    required this.publicKeyHex,
    this.signingAlgorithm = 'ed25519',
    this.custody = 'reduced_trust',
  });
}

/// Persists the account's canonical `did:elix` (layered identity).
///
/// The canonical identity is `did:elix` — derived from the identity key +
/// handle, never `did:plc` (which is only an opt-in Bluesky alias). This store
/// is the boot-time source of truth for "who am I" so `main.dart` does not have
/// to reconstruct it from scattered key material.
abstract class CanonicalIdentityStore {
  Future<void> save(CanonicalIdentity identity);
  Future<CanonicalIdentity?> load();
  Future<void> delete();
}

/// Production implementation backed by `flutter_secure_storage`.
class SecureCanonicalIdentityStore implements CanonicalIdentityStore {
  final FlutterSecureStorage _storage;

  const SecureCanonicalIdentityStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kDid = 'ansible_canonical_did';
  static const _kHandle = 'ansible_canonical_handle';
  static const _kPublicKey = 'ansible_canonical_public_key';
  static const _kAlgorithm = 'ansible_canonical_signing_algorithm';
  static const _kCustody = 'ansible_canonical_custody';

  @override
  Future<void> save(CanonicalIdentity identity) async {
    await _storage.write(key: _kDid, value: identity.did);
    await _storage.write(key: _kHandle, value: identity.handle);
    await _storage.write(key: _kPublicKey, value: identity.publicKeyHex);
    await _storage.write(key: _kAlgorithm, value: identity.signingAlgorithm);
    await _storage.write(key: _kCustody, value: identity.custody);
  }

  @override
  Future<CanonicalIdentity?> load() async {
    final did = await _storage.read(key: _kDid);
    final handle = await _storage.read(key: _kHandle);
    final publicKeyHex = await _storage.read(key: _kPublicKey);
    final signingAlgorithm = await _storage.read(key: _kAlgorithm) ?? 'ed25519';
    final custody = await _storage.read(key: _kCustody) ?? 'reduced_trust';
    if (did == null || handle == null || publicKeyHex == null) return null;
    return CanonicalIdentity(
      did: did,
      handle: handle,
      publicKeyHex: publicKeyHex,
      signingAlgorithm: signingAlgorithm,
      custody: custody,
    );
  }

  @override
  Future<void> delete() async {
    await _storage.delete(key: _kDid);
    await _storage.delete(key: _kHandle);
    await _storage.delete(key: _kPublicKey);
    await _storage.delete(key: _kAlgorithm);
    await _storage.delete(key: _kCustody);
  }
}

/// In-memory implementation for tests.
class InMemoryCanonicalIdentityStore implements CanonicalIdentityStore {
  CanonicalIdentity? _current;

  InMemoryCanonicalIdentityStore([this._current]);

  @override
  Future<void> save(CanonicalIdentity identity) async => _current = identity;

  @override
  Future<CanonicalIdentity?> load() async => _current;

  @override
  Future<void> delete() async => _current = null;
}
