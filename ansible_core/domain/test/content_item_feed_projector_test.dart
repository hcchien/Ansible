import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('ContentItemFeedProjector', () {
    late InMemoryContentItemRepository contentRepo;
    late InMemoryFollowRepository followRepo;
    final now = DateTime.utc(2026, 6, 4);

    setUp(() {
      contentRepo = InMemoryContentItemRepository();
      followRepo = InMemoryFollowRepository();
    });

    Future<void> followUser(String did) async {
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

    ContentItem item({
      required String id,
      required String authorDid,
      required ContentMode mode,
      ContentVisibility visibility = ContentVisibility.public,
      ContentStatus status = ContentStatus.active,
      DateTime? publishedAt,
    }) {
      return ContentItem(
        id: id,
        authorDid: authorDid,
        mode: mode,
        body: 'body-$id',
        status: status,
        visibility: visibility,
        createdAt: now,
        updatedAt: now,
        publishedAt: publishedAt ?? now,
        localOnly: false,
      );
    }

    test('returns followed users public murmur and note, excludes others', () async {
      await followUser('did:key:alice');

      await contentRepo.create(item(
        id: 'm1',
        authorDid: 'did:key:alice',
        mode: ContentMode.murmur,
        publishedAt: DateTime.utc(2026, 6, 4, 9),
      ));
      await contentRepo.create(item(
        id: 'n1',
        authorDid: 'did:key:alice',
        mode: ContentMode.note,
        visibility: ContentVisibility.unlisted,
        publishedAt: DateTime.utc(2026, 6, 4, 10),
      ));
      // excluded: private
      await contentRepo.create(item(
        id: 'priv',
        authorDid: 'did:key:alice',
        mode: ContentMode.note,
        visibility: ContentVisibility.private,
      ));
      // excluded: not followed
      await contentRepo.create(item(
        id: 'bob',
        authorDid: 'did:key:bob',
        mode: ContentMode.murmur,
      ));

      final projector = ContentItemFeedProjector(
        followRepository: followRepo,
        contentItemRepository: contentRepo,
      );

      final entries = await projector.project(followerDid: 'did:key:local');

      expect(entries.map((e) => e.item.id), ['n1', 'm1']); // newest first
      expect(entries.every((e) => e.reasons.contains(FollowFeedReason.followedUser)), isTrue);
    });

    test('empty when following no one', () async {
      await contentRepo.create(item(
        id: 'm1',
        authorDid: 'did:key:alice',
        mode: ContentMode.murmur,
      ));

      final projector = ContentItemFeedProjector(
        followRepository: followRepo,
        contentItemRepository: contentRepo,
      );

      expect(await projector.project(followerDid: 'did:key:local'), isEmpty);
    });
  });
}
