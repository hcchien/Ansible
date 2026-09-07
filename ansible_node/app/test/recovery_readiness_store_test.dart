import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/services/recovery_readiness_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CanonicalIdentity account(String did, String key) =>
    CanonicalIdentity(did: did, handle: 'test.elix.cool', publicKeyHex: key);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generated is not saved; records belong to DID and key epoch', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesRecoveryReadinessStore.backupCreatedAtKey:
          '2026-01-01T00:00:00Z',
    });
    final alice = account('did:elix:alice', 'aa');
    final identities = InMemoryCanonicalIdentityStore(alice);
    final store = SharedPreferencesRecoveryReadinessStore(
      identityStore: identities,
    );
    expect(
      await store.hasBackup(),
      false,
      reason: 'legacy global flag cannot identify this account',
    );
    await store.markBackupCreated(identity: alice);
    expect(await store.hasBackup(), true);
    expect(await store.hasSavedBackup(), false);
    await store.markBackupSaved(identity: alice);
    expect(await store.hasSavedBackup(), true);
    await identities.save(account('did:elix:bob', 'aa'));
    expect(await store.hasBackup(), false);
    await expectLater(store.markBackupSaved(identity: alice), throwsStateError);
    await identities.save(account(alice.did, 'bb'));
    expect(await store.hasBackup(), false);
    await expectLater(
      store.markBackupCreated(identity: alice),
      throwsStateError,
    );
    await identities.save(alice);
    expect(await store.hasSavedBackup(), true);
    await store.markBackupCreated(identity: alice);
    expect(await store.hasSavedBackup(), false);
    await store.clearBackup();
    expect(await store.hasBackup(), false);
    await expectLater(store.markBackupSaved(), throwsStateError);
    await identities.delete();
    expect(await store.hasSavedBackup(), false);
  });
}
