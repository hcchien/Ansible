import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('DidReputationRepository', () {
    test('drift upserts and reads tiers', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final repo = DriftDidReputationRepository(db);

      expect(await repo.tierFor('did:key:alice'), 'basic'); // unknown default

      await repo.put('did:key:alice', 'verified_human');
      await repo.put('did:key:bob', 'basic');
      // Upsert replaces.
      await repo.put('did:key:alice', 'verified_human');

      expect(await repo.tierFor('did:key:alice'), 'verified_human');
      final map = await repo.tiersFor(['did:key:alice', 'did:key:bob', 'did:key:none']);
      expect(map['did:key:alice'], 'verified_human');
      expect(map['did:key:bob'], 'basic');
      expect(map.containsKey('did:key:none'), isFalse);
      expect(await repo.list(), hasLength(2));
    });

    test('in-memory matches the interface', () async {
      final repo = InMemoryDidReputationRepository();
      expect(await repo.tierFor('did:key:x'), 'basic');
      await repo.put('did:key:x', 'verified_human');
      expect(await repo.tierFor('did:key:x'), 'verified_human');
      expect((await repo.tiersFor(['did:key:x']))['did:key:x'], 'verified_human');
    });
  });
}
