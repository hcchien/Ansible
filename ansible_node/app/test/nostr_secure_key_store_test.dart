import 'package:ansible_node/services/nostr_secure_key_store.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageNostrKeyStore', () {
    const storage = FlutterSecureStorage();

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('saves, reads, and clears Nostr key material', () async {
      final store = SecureStorageNostrKeyStore(secureStorage: storage);
      final key = NostrKeyMaterial(
        privateKeyHex: 'a' * 64,
        publicKeyHex: 'b' * 64,
      );

      await store.save(key);
      expect(await store.read(), key);

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('returns null for partial key material', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageNostrKeyStore.privateKeyStorageKey: 'a' * 64,
      });

      final store = SecureStorageNostrKeyStore(secureStorage: storage);

      expect(await store.read(), isNull);
    });
  });
}
