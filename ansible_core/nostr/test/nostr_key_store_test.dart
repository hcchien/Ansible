import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:test/test.dart';

void main() {
  group('NostrKeyStore', () {
    test('saves, reads, and clears key material', () async {
      final store = InMemoryNostrKeyStore();
      final key = NostrKeyMaterial(
        privateKeyHex: 'a' * 64,
        publicKeyHex: 'b' * 64,
      );

      await store.save(key);
      expect(await store.read(), key);

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('rejects malformed private or public keys', () {
      expect(
        () =>
            NostrKeyMaterial(privateKeyHex: 'dev-key', publicKeyHex: 'b' * 64),
        throwsArgumentError,
      );
      expect(
        () => NostrKeyMaterial(privateKeyHex: 'a' * 64, publicKeyHex: 'stub'),
        throwsArgumentError,
      );
    });
  });
}
