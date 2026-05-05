import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('FollowService', () {
    late InMemoryFollowRepository followRepo;
    late InMemoryFollowActivityOutboxRepository outboxRepo;
    late InMemoryBoardSyncConfigRepository boardSyncRepo;
    late FollowService service;

    setUp(() {
      followRepo = InMemoryFollowRepository();
      outboxRepo = InMemoryFollowActivityOutboxRepository();
      boardSyncRepo = InMemoryBoardSyncConfigRepository();
      service = FollowService(
        followRepository: followRepo,
        outboxRepository: outboxRepo,
        boardSyncConfigRepository: boardSyncRepo,
        idFactory: _SequenceIds(),
      );
    });

    test('follow local user creates accepted local edge', () async {
      final result = await service.followUser(
        followerDid: 'did:key:local',
        targetDid: 'did:key:alice',
        displayName: 'Alice',
        now: DateTime.utc(2026, 5, 4),
      );

      expect(result.status, FollowResultStatus.success);
      final edges = await followRepo.listFollowing('did:key:local');
      expect(edges.single.status, FollowStatus.accepted);
      expect(edges.single.visibility, FollowVisibility.localOnly);
    });

    test('follow remote user queues federated Follow', () async {
      await service.followUser(
        followerDid: 'did:key:local',
        actorUri: 'https://remote.example/users/alice',
        inboxUri: 'https://remote.example/users/alice/inbox',
        displayName: 'Alice',
        now: DateTime.utc(2026, 5, 4),
      );

      final target = await followRepo.getTargetByCanonicalUri(
        'https://remote.example/users/alice',
      );
      final edge = await followRepo.getEdge(
        'did:key:local',
        target!.targetId,
        FollowDirection.outbound,
      );
      final outbox = await outboxRepo.listQueued();

      expect(edge!.status, FollowStatus.pending);
      expect(outbox.single.activityType, OutboundFollowActivityType.follow);
    });

    test('follow remote board enables board sync config', () async {
      await service.followBoard(
        followerDid: 'did:key:local',
        remoteNodeId: 'remote-1',
        boardId: 'board-1',
        boardSlug: 'civic-tech',
        displayName: 'Civic Tech',
        now: DateTime.utc(2026, 5, 4),
      );

      final config = await boardSyncRepo.getByRemoteAndBoard(
        'remote-1',
        'board-1',
      );
      expect(config!.syncEnabled, isTrue);
    });

    test('following the same local board returns duplicate result', () async {
      await service.followBoard(
        followerDid: 'did:key:local',
        boardId: 'board-1',
        boardSlug: 'civic-tech',
        displayName: 'Civic Tech',
        now: DateTime.utc(2026, 5, 4),
      );

      final result = await service.followBoard(
        followerDid: 'did:key:local',
        boardId: 'board-1',
        boardSlug: 'civic-tech',
        displayName: 'Civic Tech',
        now: DateTime.utc(2026, 5, 4, 0, 1),
      );

      final edges = await followRepo.listFollowing(
        'did:key:local',
        targetType: FollowTargetType.board,
      );
      expect(result.status, FollowResultStatus.duplicate);
      expect(edges, hasLength(1));
    });

    test('unfollow remote board disables sync and queues Undo', () async {
      final followResult = await service.followBoard(
        followerDid: 'did:key:local',
        remoteNodeId: 'remote-1',
        boardId: 'board-1',
        boardSlug: 'civic-tech',
        actorUri: 'https://remote.example/boards/board-1',
        inboxUri: 'https://remote.example/inbox',
        displayName: 'Civic Tech',
        now: DateTime.utc(2026, 5, 4),
      );
      final target = await followRepo.getBoardTarget('remote-1', 'board-1');

      await service.unfollow(
        followerDid: 'did:key:local',
        targetId: target!.targetId,
        now: DateTime.utc(2026, 5, 4, 0, 1),
      );

      final config = await boardSyncRepo.getByRemoteAndBoard(
        'remote-1',
        'board-1',
      );
      final outbox = await outboxRepo.listQueued();

      expect(followResult.status, FollowResultStatus.success);
      expect(config!.syncEnabled, isFalse);
      expect(outbox.map((item) => item.activityType), [
        OutboundFollowActivityType.follow,
        OutboundFollowActivityType.undo,
      ]);
    });
  });
}

class _SequenceIds implements FollowIdFactory {
  var _next = 0;

  @override
  String next(String prefix) {
    _next += 1;
    return '$prefix-$_next';
  }
}
