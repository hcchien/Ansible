import 'package:ansible_did/ansible_did.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Removes the identity material held by this device only.
///
/// This is intentionally local-only: it does not revoke a DID, credential, or
/// device at a Relay.  The user can still recover with another approved device
/// or an existing backup.  App database content is also intentionally left in
/// place; without the local key material it cannot act as this identity.
abstract class LocalIdentityResetter {
  Future<void> eraseLocalIdentity();
}

/// Production eraser for the Keychain entries and the Secure Enclave identity
/// key owned by Elix.
class LocalIdentityResetService implements LocalIdentityResetter {
  LocalIdentityResetService({
    FlutterSecureStorage? storage,
    HardwareIdentityKey? hardwareIdentityKey,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _hardwareIdentityKey = hardwareIdentityKey ?? HardwareIdentityKey();

  final FlutterSecureStorage _storage;
  final HardwareIdentityKey _hardwareIdentityKey;

  @override
  Future<void> eraseLocalIdentity() async {
    // The non-exportable P-256 key does not live in FlutterSecureStorage, so
    // it must be removed explicitly before clearing Keychain-backed metadata.
    // Platform implementations treat a missing key as a successful no-op.
    await _hardwareIdentityKey.delete();

    // FlutterSecureStorage uses this app's Keychain access group.  Clearing it
    // removes canonical DID metadata, legacy/passkey keys, recovery-device
    // keys, and any Nostr key material that belongs to this installation.
    await _storage.deleteAll();
  }
}
