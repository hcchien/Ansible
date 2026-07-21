import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('AppViewTimelineSource', () {
    late InMemoryFollowRepository followRepo;
    final now = DateTime.utc(2026, 6, 5);

    setUp(() {
      followRepo = InMemoryFollowRepository();
    });

    Future<void> followFederated(String did) async {
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'target-$did',
          targetType: FollowTargetType.user,
          canonicalUri: did,
          displayName: did,
          did: did,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-$did',
          followerDid: 'did:key:local',
          targetId: 'target-$did',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.federated,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );
    }

    // Native Elix follows (no ActivityPub inbox) are localOnly. They must still
    // be queried against the AppView — regression guard for the empty-timeline
    // bug where only federated follows were sent.
    Future<void> followLocalOnly(String did) async {
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'target-$did',
          targetType: FollowTargetType.user,
          canonicalUri: did,
          displayName: did,
          did: did,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-$did',
          followerDid: 'did:key:local',
          targetId: 'target-$did',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );
    }

    test('queries native localOnly follow DIDs too', () async {
      await followLocalOnly('did:elix:bob');

      List<String>? requestedDids;
      final source = AppViewTimelineSource(
        followRepository: followRepo,
        fetcher: ({required dids, cursor, limit = 50}) async {
          requestedDids = dids;
          return const AppViewTimelinePage(items: []);
        },
      );

      await source.fetch(followerDid: 'did:key:local');

      expect(requestedDids, ['did:elix:bob']);
    });

    test('queries federated follow DIDs and maps items', () async {
      await followFederated('did:key:alice');

      List<String>? requestedDids;
      final source = AppViewTimelineSource(
        followRepository: followRepo,
        fetcher: ({required dids, cursor, limit = 50}) async {
          requestedDids = dids;
          return AppViewTimelinePage(
            items: [
              AppViewTimelineItem(
                entityType: 'murmur',
                entityId: 'm1',
                authorDid: 'did:key:alice',
                visibility: 'public',
                createdAt: now,
                payload: const {'body': 'hi'},
              ),
              AppViewTimelineItem(
                entityType: 'post',
                entityId: 'p1',
                authorDid: 'did:key:alice',
                boardId: 'b1',
                threadId: 't1',
                createdAt: now,
                payload: const {'content': 'a post'},
              ),
            ],
            nextCursor: 42,
            hasMore: true,
          );
        },
      );

      final page = await source.fetch(followerDid: 'did:key:local');

      expect(requestedDids, ['did:key:alice']);
      expect(page.items.whereType<ContentTimelineItem>().length, 1);
      expect(page.items.whereType<PostTimelineItem>().length, 1);
      expect(
        page.items.whereType<ContentTimelineItem>().single.signatureVerified,
        isTrue,
      );
      expect(
        page.items.whereType<PostTimelineItem>().single.signatureVerified,
        isTrue,
      );
      expect(page.nextCursor, 42);
      expect(page.hasMore, isTrue);
    });

    test('skips board-less comment posts (comments on content)', () async {
      await followFederated('did:key:alice');

      final source = AppViewTimelineSource(
        followRepository: followRepo,
        fetcher: ({required dids, cursor, limit = 50}) async {
          return AppViewTimelinePage(
            items: [
              // A comment on a murmur: post with empty board, threadId = content.
              AppViewTimelineItem(
                entityType: 'post',
                entityId: 'c1',
                authorDid: 'did:key:alice',
                boardId: '',
                threadId: 'murmur-1',
                createdAt: now,
                payload: const {'content': 'a comment'},
              ),
              // A real forum post: keeps showing.
              AppViewTimelineItem(
                entityType: 'post',
                entityId: 'p1',
                authorDid: 'did:key:alice',
                boardId: 'b1',
                threadId: 't1',
                createdAt: now,
                payload: const {'content': 'a post'},
              ),
            ],
          );
        },
      );

      final page = await source.fetch(followerDid: 'did:key:local');

      // Only the board-backed forum post survives; the comment is excluded.
      expect(page.items.whereType<PostTimelineItem>().length, 1);
    });

    test('uses homeFetcher (fan-out-on-write) with reader DID, skips follow set', () async {
      var fetcherCalled = false;
      String? requestedReader;

      final source = AppViewTimelineSource(
        followRepository: followRepo,
        fetcher: ({required dids, cursor, limit = 50}) async {
          fetcherCalled = true;
          return const AppViewTimelinePage(items: []);
        },
        homeFetcher: ({required readerDid, cursor, limit = 50}) async {
          requestedReader = readerDid;
          return AppViewTimelinePage(
            items: [
              AppViewTimelineItem(
                entityType: 'murmur',
                entityId: 'm1',
                authorDid: 'did:key:alice',
                visibility: 'public',
                createdAt: now,
                payload: const {'body': 'fanned'},
              ),
            ],
            nextCursor: 7,
            hasMore: false,
          );
        },
      );

      // No federated follows configured: home path must still return items
      // (the server materialized them), and the dids fetcher is never called.
      final page = await source.fetch(followerDid: 'did:key:local');

      expect(requestedReader, 'did:key:local');
      expect(fetcherCalled, isFalse);
      expect(page.items.whereType<ContentTimelineItem>().length, 1);
      expect(page.nextCursor, 7);
    });

    test('returns empty without calling fetcher when no federated follows', () async {
      var called = false;
      final source = AppViewTimelineSource(
        followRepository: followRepo,
        fetcher: ({required dids, cursor, limit = 50}) async {
          called = true;
          return const AppViewTimelinePage(items: []);
        },
      );

      final page = await source.fetch(followerDid: 'did:key:local');
      expect(page.items, isEmpty);
      expect(called, isFalse);
    });
  });
}
