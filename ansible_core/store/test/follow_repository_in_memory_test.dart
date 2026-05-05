import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryFollowRepository', () {
    late InMemoryFollowRepository followRepo;
    late InMemoryFollowActivityOutboxRepository outboxRepo;

    setUp(() {
      followRepo = InMemoryFollowRepository();
      outboxRepo = InMemoryFollowActivityOutboxRepository();
    });

    test('upserts target and effective follow edge', () async {
      final now = DateTime.utc(2026, 5, 4);
      final target = FollowTarget(
        targetId: 'target-alice',
        targetType: FollowTargetType.user,
        canonicalUri: 'https://example.social/users/alice',
        displayName: 'Alice',
        did: 'did:key:alice',
        actorUri: 'https://example.social/users/alice',
        inboxUri: 'https://example.social/users/alice/inbox',
        createdAt: now,
        updatedAt: now,
      );
      await followRepo.upsertTarget(target);

      final edge = FollowEdge(
        followId: 'follow-1',
        followerDid: 'did:key:local',
        targetId: target.targetId,
        targetType: FollowTargetType.user,
        direction: FollowDirection.outbound,
        status: FollowStatus.pending,
        visibility: FollowVisibility.federated,
        remoteActivityId: 'https://node.example/activities/follow/1',
        createdAt: now,
        updatedAt: now,
      );
      await followRepo.upsertEdge(edge);

      final loadedTarget = await followRepo.getTargetByCanonicalUri(
        target.canonicalUri!,
      );
      final loadedEdge = await followRepo.getEdge(
        edge.followerDid,
        target.targetId,
        FollowDirection.outbound,
      );

      expect(loadedTarget!.displayName, 'Alice');
      expect(loadedEdge!.status, FollowStatus.pending);
    });

    test('lists following by target type', () async {
      final now = DateTime.utc(2026, 5, 4);
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'board-1-target',
          targetType: FollowTargetType.board,
          canonicalUri: 'local://boards/board-1',
          displayName: 'Civic Tech',
          boardId: 'board-1',
          boardSlug: 'civic-tech',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-board-1',
          followerDid: 'did:key:local',
          targetId: 'board-1-target',
          targetType: FollowTargetType.board,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );

      final boards = await followRepo.listFollowing(
        'did:key:local',
        targetType: FollowTargetType.board,
      );

      expect(boards, hasLength(1));
      expect(boards.single.targetId, 'board-1-target');
    });

    test('records follow activity events', () async {
      final now = DateTime.utc(2026, 5, 4);
      await followRepo.recordEvent(
        FollowActivityEvent(
          eventId: 'event-1',
          followId: 'follow-1',
          eventType: FollowActivityEventType.followRequested,
          actorDid: 'did:key:local',
          activityId: 'https://node.example/activities/follow/1',
          createdAt: now,
        ),
      );

      final events = await followRepo.listEvents('follow-1');

      expect(events.single.eventType, FollowActivityEventType.followRequested);
    });

    test('queues and marks outbound follow activities', () async {
      final now = DateTime.utc(2026, 5, 4);
      await outboxRepo.enqueue(
        OutboundFollowActivity(
          outboxId: 'outbox-1',
          activityId: 'https://node.example/activities/follow/1',
          activityType: OutboundFollowActivityType.follow,
          targetInboxUri: 'https://example.social/users/alice/inbox',
          payloadJson: '{"type":"Follow"}',
          status: OutboundFollowActivityStatus.queued,
          attemptCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(await outboxRepo.listQueued(), hasLength(1));

      await outboxRepo.markDelivering(
        'outbox-1',
        now.add(const Duration(seconds: 1)),
      );
      await outboxRepo.markDelivered(
        'outbox-1',
        now.add(const Duration(seconds: 2)),
      );

      expect(await outboxRepo.listQueued(), isEmpty);
    });
  });
}
