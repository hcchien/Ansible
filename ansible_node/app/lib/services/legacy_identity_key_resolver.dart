import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'canonical_identity_store.dart';

/// Resolves the software Ed25519 key retained after a hardware-key upgrade.
///
/// The key is returned only when it independently derives the current
/// self-certifying did:elix. This lets a device verify and restore its own
/// pre-rotation Relay ops without trusting the Relay to rewrite signatures.
class LegacyIdentityKeyResolver {
  LegacyIdentityKeyResolver({
    FlutterSecureStorage? secureStorage,
    CanonicalIdentityStore? identityStore,
  }) : _storage = secureStorage ?? const FlutterSecureStorage(),
       _identityStore = identityStore ?? const SecureCanonicalIdentityStore();

  final FlutterSecureStorage _storage;
  final CanonicalIdentityStore _identityStore;

  Future<String?> resolve(String did) async {
    final identity = await _identityStore.load();
    if (identity == null || identity.did != did) return null;

    final privateKeyHex = await _storage.read(key: 'ansible_did_private_key');
    if (privateKeyHex == null || privateKeyHex.isEmpty) return null;

    try {
      final publicKeyHex = await Ed25519Keys.publicKeyHexFromSeed(
        privateKeyHex,
      );
      final derivedDid = deriveDidElix(
        identityKey: publicKeyHex,
        handle: identity.handle,
      );
      return derivedDid == did ? publicKeyHex : null;
    } catch (_) {
      return null;
    }
  }
}
