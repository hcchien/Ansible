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
      expect(page.nextCursor, 42);
      expect(page.hasMore, isTrue);
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
