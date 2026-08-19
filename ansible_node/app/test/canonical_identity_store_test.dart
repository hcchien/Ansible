import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'secure store round-trips and deletes the v1 genesis commitment',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = SecureCanonicalIdentityStore();
      final commitment = <String, Object?>{
        'method': 'did:elix',
        'method_version': 1,
        'genesis_key': 'aa' * 32,
        'genesis_nonce': '01' * 32,
      };

      await store.save(
        CanonicalIdentity(
          did: 'did:elix:zexample',
          handle: 'alice.elix.cool',
          publicKeyHex: 'aa' * 32,
          genesisCommitment: commitment,
        ),
      );

      expect((await store.load())?.genesisCommitment, commitment);
      await store.delete();
      expect(await store.load(), isNull);
    },
  );
}
