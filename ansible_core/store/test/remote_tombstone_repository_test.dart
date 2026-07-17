import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('Drift tombstones are source scoped and removable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftRemoteTombstoneRepository(db);
    final now = DateTime.utc(2026, 7, 17);

    for (final source in ['relay-a', 'relay-b']) {
      await repo.upsert(
        RemoteTombstone(
          sourceNodeId: source,
          entityType: 'post',
          entityId: 'post-1',
          deletedByDid: 'did:elix:moderator',
          deletedAt: now,
          receivedAt: now,
        ),
      );
    }

    await repo.remove('relay-a', 'post', 'post-1');

    expect(await repo.get('relay-a', 'post', 'post-1'), isNull);
    expect(await repo.get('relay-b', 'post', 'post-1'), isNotNull);
  });
}
