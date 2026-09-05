import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('Drift posts persist signed mention profile references', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 9, 5);
    await DriftBoardRepository(db).create(
      Board(
        id: 'board-1',
        slug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await DriftThreadRepository(db).create(
      Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'Mentions',
        authorId: 'did:elix:author',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final repository = DriftPostRepository(db);
    await repository.create(
      Post(
        id: 'post-1',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: 'did:elix:author',
        content: 'Hello @Alice',
        mentions: const [PostMention(did: 'did:elix:alice', token: '@Alice')],
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      ),
    );

    final stored = await repository.getById('post-1');
    expect(stored?.mentions, hasLength(1));
    expect(stored?.mentions.single.did, 'did:elix:alice');
    expect(stored?.mentions.single.token, '@Alice');
  });
}
