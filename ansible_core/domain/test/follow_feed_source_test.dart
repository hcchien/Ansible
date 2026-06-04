import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('LocalDeltaFilterSource', () {
    late InMemoryFollowRepository followRepo;
    late InMemoryBoardRepository boardRepo;
    late InMemoryThreadRepository threadRepo;
    late InMemoryPostRepository postRepo;
    late InMemoryContentItemRepository contentRepo;
    late LocalDeltaFilterSource source;
    final now = DateTime.utc(2026, 6, 4);

    setUp(() async {
      followRepo = InMemoryFollowRepository();
      boardRepo = InMemoryBoardRepository();
      threadRepo = InMemoryThreadRepository();
      postRepo = InMemoryPostRepository();
      contentRepo = InMemoryContentItemRepository();

      // Follow alice.
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'target-alice',
          targetType: FollowTargetType.user,
          canonicalUri: 'did:key:alice',
          displayName: 'Alice',
          did: 'did:key:alice',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-alice',
          followerDid: 'did:key:local',
          targetId: 'target-alice',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.federated,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );

      // A board post by alice (in a board the user does not follow, but the
      // author is followed — board projector still surfaces it when the post is
      // local; here we follow the board too so the post is included).
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'target-board',
          targetType: FollowTargetType.board,
          canonicalUri: 'local://boards/board-1',
          displayName: 'Board',
          boardId: 'board-1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-board',
          followerDid: 'did:key:local',
          targetId: 'target-board',
          targetType: FollowTargetType.board,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );
      await boardRepo.create(Board(
        id: 'board-1',
        slug: 'b1',
        title: 'B1',
        createdAt: now,
        updatedAt: now,
      ));
      await threadRepo.create(Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'T',
        authorId: 'did:key:alice',
        createdAt: now,
        updatedAt: now,
      ));
      await postRepo.create(Post(
        id: 'post-1',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: 'did:key:alice',
        content: 'hi',
        createdAt: now,
        updatedAt: now,
        lastEditAt: DateTime.utc(2026, 6, 4, 8),
      ));

      // A murmur by alice, newer than the post.
      await contentRepo.create(ContentItem(
        id: 'murmur-1',
        authorDid: 'did:key:alice',
        mode: ContentMode.murmur,
        body: 'thought',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        createdAt: now,
        updatedAt: now,
        publishedAt: DateTime.utc(2026, 6, 4, 11),
        localOnly: false,
      ));

      source = LocalDeltaFilterSource(
        postProjector: FollowFeedProjector(
          followRepository: followRepo,
          boardRepository: boardRepo,
          threadRepository: threadRepo,
          postRepository: postRepo,
        ),
        contentProjector: ContentItemFeedProjector(
          followRepository: followRepo,
          contentItemRepository: contentRepo,
        ),
      );
    });

    test('merges posts and murmur/note newest-first', () async {
      final page = await source.fetch(followerDid: 'did:key:local');

      expect(page.items, hasLength(2));
      // murmur (11:00) is newer than post (08:00)
      expect(page.items.first, isA<ContentTimelineItem>());
      expect(page.items.last, isA<PostTimelineItem>());
      expect(page.hasMore, isFalse);
    });

    test('paginates with an opaque cursor', () async {
      final first = await source.fetch(followerDid: 'did:key:local', limit: 1);
      expect(first.items, hasLength(1));
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, isNotNull);

      final second = await source.fetch(
        followerDid: 'did:key:local',
        cursor: first.nextCursor,
        limit: 1,
      );
      expect(second.items, hasLength(1));
      expect(second.hasMore, isFalse);
      // Different items across pages.
      expect(
        second.items.single.runtimeType,
        isNot(first.items.single.runtimeType),
      );
    });
  });
}
