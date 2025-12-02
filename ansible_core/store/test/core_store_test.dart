import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('Core Store Tests', () {
    late BoardRepository boardRepo;
    late ThreadRepository threadRepo;
    late PostRepository postRepo;

    setUp(() {
      boardRepo = InMemoryBoardRepository();
      threadRepo = InMemoryThreadRepository();
      postRepo = InMemoryPostRepository();
    });

    test('Create and retrieve Board', () async {
      final now = DateTime.now();
      final board = Board(
        id: 'board-1',
        slug: 'tech',
        title: 'Technology',
        description: 'General tech discussion',
        createdAt: now,
        updatedAt: now,
      );

      await boardRepo.create(board);
      final retrieved = await boardRepo.getById('board-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Technology');
      expect(retrieved.slug, 'tech');
    });

    test('Create and retrieve Thread linked to Board', () async {
      final now = DateTime.now();
      final thread = Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'Dart is awesome',
        authorId: 'user-123',
        createdAt: now,
        updatedAt: now,
      );

      await threadRepo.create(thread);
      final retrieved = await threadRepo.getById('thread-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.boardId, 'board-1');
    });

    test('Create and retrieve Post linked to Thread', () async {
      final now = DateTime.now();
      final post = Post(
        id: 'post-1',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: 'user-123',
        content: 'Hello World',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      );

      await postRepo.create(post);
      final retrieved = await postRepo.getById('post-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.threadId, 'thread-1');
      expect(retrieved.content, 'Hello World');
    });

    test('List Threads by Board', () async {
      final now = DateTime.now();
      final t1 = Thread(
        id: 't1',
        boardId: 'b1',
        title: 'T1',
        authorId: 'user-1',
        createdAt: now,
        updatedAt: now,
      );
      final t2 = Thread(
        id: 't2',
        boardId: 'b1',
        title: 'T2',
        authorId: 'user-1',
        createdAt: now,
        updatedAt: now,
      );
      final t3 = Thread(
        id: 't3',
        boardId: 'b2',
        title: 'T3',
        authorId: 'user-1',
        createdAt: now,
        updatedAt: now,
      );

      await threadRepo.create(t1);
      await threadRepo.create(t2);
      await threadRepo.create(t3);

      final b1Threads = await threadRepo.list(boardId: 'b1');
      expect(b1Threads.length, 2);
      expect(b1Threads.map((t) => t.id), containsAll(['t1', 't2']));
    });
  });
}
