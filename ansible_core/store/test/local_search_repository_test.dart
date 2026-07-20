import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test(
    'searches all canonical local content without a network source',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 7, 20);
      await DriftBoardRepository(db).create(
        Board(
          id: 'board-1',
          slug: 'local-search',
          title: '離線看板',
          description: '搜尋關鍵字',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await DriftThreadRepository(db).create(
        Thread(
          id: 'thread-1',
          boardId: 'board-1',
          title: '搜尋關鍵字討論',
          authorId: 'did:elix:alice',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await DriftPostRepository(db).create(
        Post(
          id: 'post-1',
          threadId: 'thread-1',
          boardId: 'board-1',
          authorId: 'did:elix:alice',
          content: '貼文也有搜尋關鍵字',
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
        ),
      );
      await DriftContentItemRepository(db).create(
        ContentItem(
          id: 'note-1',
          authorDid: 'did:elix:alice',
          mode: ContentMode.note,
          title: '本機筆記',
          body: '私密搜尋關鍵字',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          localOnly: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final repo = DriftLocalSearchRepository(db);

      final all = await repo.search('搜尋關鍵字');
      expect(
        all.map((result) => result.kind),
        containsAll([
          LocalSearchKind.board,
          LocalSearchKind.thread,
          LocalSearchKind.post,
          LocalSearchKind.note,
        ]),
      );

      final private = await repo.search(
        '搜尋關鍵字',
        scope: LocalSearchScope.private,
      );
      expect(private.map((result) => result.kind), [LocalSearchKind.note]);
      expect(private.single.localOnly, isTrue);
    },
  );
}
