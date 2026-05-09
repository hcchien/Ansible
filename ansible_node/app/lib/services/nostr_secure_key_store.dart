import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageNostrKeyStore implements NostrKeyStore {
  static const privateKeyStorageKey = 'ansible_nostr_private_key';
  static const publicKeyStorageKey = 'ansible_nostr_public_key';

  final FlutterSecureStorage _secureStorage;

  const SecureStorageNostrKeyStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<NostrKeyMaterial?> read() async {
    final privateKeyHex = await _secureStorage.read(key: privateKeyStorageKey);
    final publicKeyHex = await _secureStorage.read(key: publicKeyStorageKey);
    if (privateKeyHex == null || publicKeyHex == null) return null;
    return NostrKeyMaterial(
      privateKeyHex: privateKeyHex,
      publicKeyHex: publicKeyHex,
    );
  }

  @override
  Future<void> save(NostrKeyMaterial key) async {
    await _secureStorage.write(
      key: privateKeyStorageKey,
      value: key.privateKeyHex,
    );
    await _secureStorage.write(
      key: publicKeyStorageKey,
      value: key.publicKeyHex,
    );
  }

  @override
  Future<void> clear() async {
    await _secureStorage.delete(key: privateKeyStorageKey);
    await _secureStorage.delete(key: publicKeyStorageKey);
  }
}
