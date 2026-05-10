import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('local collections group local content without forum boards', () async {
    final repo = InMemoryLocalCollectionRepository();
    final now = DateTime.utc(2026, 5, 10);

    await repo.upsert(
      LocalCollection(
        collectionId: 'collection-1',
        ownerDid: 'did:key:z6MkUser',
        title: 'Research',
        description: 'Private local grouping',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final collection = await repo.getById('collection-1');
    expect(collection!.ownerDid, 'did:key:z6MkUser');
    expect(collection.title, 'Research');
    expect(collection.isDeleted, isFalse);
  });

  test('drift local collections are independent from board tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final collections = DriftLocalCollectionRepository(db);
    final boards = DriftBoardRepository(db);
    final now = DateTime.utc(2026, 5, 10);

    await collections.upsert(
      LocalCollection(
        collectionId: 'collection-1',
        ownerDid: 'did:key:z6MkUser',
        title: 'Reading',
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(await boards.list(), isEmpty);
    expect(
      (await collections.list(ownerDid: 'did:key:z6MkUser')).single.title,
      'Reading',
    );
  });
}
