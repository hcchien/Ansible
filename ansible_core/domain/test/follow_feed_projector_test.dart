import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('FollowFeedProjector', () {
    test('deduplicates posts matching followed user and board', () async {
      final followRepo = InMemoryFollowRepository();
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final now = DateTime.utc(2026, 5, 4);

      await boardRepo.create(
        Board(
          id: 'board-1',
          slug: 'civic-tech',
          title: 'Civic Tech',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await threadRepo.create(
        Thread(
          id: 'thread-1',
          boardId: 'board-1',
          title: 'Hello',
          authorId: 'did:key:alice',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await postRepo.create(
        Post(
          id: 'post-1',
          threadId: 'thread-1',
          boardId: 'board-1',
          authorId: 'did:key:alice',
          content: 'Hello world',
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
        ),
      );

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
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'target-board-1',
          targetType: FollowTargetType.board,
          canonicalUri: 'local://boards/board-1',
          displayName: 'Civic Tech',
          boardId: 'board-1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-user',
          followerDid: 'did:key:local',
          targetId: 'target-alice',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-board',
          followerDid: 'did:key:local',
          targetId: 'target-board-1',
          targetType: FollowTargetType.board,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );

      final projector = FollowFeedProjector(
        followRepository: followRepo,
        boardRepository: boardRepo,
        threadRepository: threadRepo,
        postRepository: postRepo,
      );

      final entries = await projector.project(followerDid: 'did:key:local');

      expect(entries, hasLength(1));
      expect(entries.single.post.id, 'post-1');
      expect(entries.single.reasons, contains(FollowFeedReason.followedUser));
      expect(entries.single.reasons, contains(FollowFeedReason.followedBoard));
    });
  });
}
