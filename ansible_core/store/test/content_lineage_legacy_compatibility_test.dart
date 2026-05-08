import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('content lineage legacy compatibility', () {
    late AppDatabase db;
    late DriftBoardRepository boards;
    late DriftThreadRepository threads;
    late DriftPostRepository posts;
    late DriftContentItemRepository contentItems;
    late DriftContentRelationRepository contentRelations;
    late DriftProjectionRepository projections;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      boards = DriftBoardRepository(db);
      threads = DriftThreadRepository(db);
      posts = DriftPostRepository(db);
      contentItems = DriftContentItemRepository(db);
      contentRelations = DriftContentRelationRepository(db);
      projections = DriftProjectionRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('legacy board thread and post repositories keep working', () async {
      final now = DateTime.utc(2026, 5, 8, 12);
      await boards.create(
        Board(
          id: 'board-1',
          slug: 'civic-tech',
          title: 'Civic Tech',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await threads.create(
        Thread(
          id: 'thread-1',
          boardId: 'board-1',
          title: 'Legacy thread',
          authorId: 'did:plc:alice',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await posts.create(
        Post(
          id: 'post-1',
          threadId: 'thread-1',
          boardId: 'board-1',
          authorId: 'did:plc:alice',
          content: 'Legacy post body',
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
        ),
      );

      await contentItems.create(
        ContentItem(
          id: 'note-1',
          authorDid: 'did:plc:alice',
          mode: ContentMode.note,
          title: 'Private note',
          body: 'Private note body',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await contentItems.create(
        ContentItem(
          id: 'discussion-1',
          authorDid: 'did:plc:alice',
          mode: ContentMode.discussion,
          title: 'Projected discussion',
          body: 'Projected discussion body',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          createdAt: now,
          updatedAt: now,
          localOnly: false,
        ),
      );
      await projections.create(
        Projection(
          id: 'projection-1',
          sourceContentItemId: 'note-1',
          targetDiscussionId: 'discussion-1',
          projectedExcerpt: 'Projected discussion body',
          participationPolicy: 'public',
          ownershipTransferAcknowledged: true,
          acknowledgedAt: now,
          createdByDid: 'did:plc:alice',
          createdAt: now,
        ),
      );
      await contentRelations.create(
        ContentRelation(
          id: 'relation-1',
          fromContentItemId: 'discussion-1',
          toContentItemId: 'note-1',
          relationType: RelationType.projectedFrom,
          createdByDid: 'did:plc:alice',
          createdAt: now,
          localOnly: false,
        ),
      );

      final loadedBoard = await boards.getById('board-1');
      final loadedThread = await threads.getById('thread-1');
      final threadPosts = await posts.list(threadId: 'thread-1');

      expect(loadedBoard!.title, 'Civic Tech');
      expect(loadedThread!.title, 'Legacy thread');
      expect(threadPosts.single.content, 'Legacy post body');
      expect((await threads.list(boardId: 'board-1')).map((t) => t.id), [
        'thread-1',
      ]);
    });
  });
}
