import 'dart:convert';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_sync/ansible_sync.dart';
import 'package:test/test.dart';

void main() {
  group('FollowInboxController', () {
    test('rejects malformed follow without object', () async {
      final controller = FollowInboxController();
      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/follow/1',
        'type': 'Follow',
        'actor': 'https://remote.example/users/alice',
      });

      expect(response.statusCode, 400);
      expect(
        jsonDecode(await response.readAsString())['error'],
        'invalid_follow_activity',
      );
    });

    test('routes Accept to follow service', () async {
      final followRepo = InMemoryFollowRepository();
      final service = _buildService(followRepo);
      await service.followUser(
        followerDid: 'did:key:local',
        actorUri: 'https://remote.example/users/alice',
        inboxUri: 'https://remote.example/users/alice/inbox',
        displayName: 'Alice',
        now: DateTime.utc(2026, 5, 4),
      );

      final controller = FollowInboxController(followService: service);
      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/accept/1',
        'type': 'Accept',
        'actor': 'https://remote.example/users/alice',
        'object': {
          'id': 'local://activities/follow/follow-2',
          'type': 'Follow',
          'actor': 'did:key:local',
          'object': 'https://remote.example/users/alice',
        },
        'published': '2026-05-04T00:01:00.000Z',
      });

      final target = await followRepo.getTargetByCanonicalUri(
        'https://remote.example/users/alice',
      );
      final edge = await followRepo.getEdge(
        'did:key:local',
        target!.targetId,
        FollowDirection.outbound,
      );

      expect(response.statusCode, 200);
      expect(edge!.status, FollowStatus.accepted);
    });

    test('routes Reject to follow service', () async {
      final followRepo = InMemoryFollowRepository();
      final service = _buildService(followRepo);
      await service.followUser(
        followerDid: 'did:key:local',
        actorUri: 'https://remote.example/users/alice',
        inboxUri: 'https://remote.example/users/alice/inbox',
        displayName: 'Alice',
        now: DateTime.utc(2026, 5, 4),
      );

      final controller = FollowInboxController(followService: service);
      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/reject/1',
        'type': 'Reject',
        'actor': 'https://remote.example/users/alice',
        'object': {
          'id': 'local://activities/follow/follow-2',
          'type': 'Follow',
          'actor': 'did:key:local',
          'object': 'https://remote.example/users/alice',
        },
        'published': '2026-05-04T00:01:00.000Z',
      });

      final target = await followRepo.getTargetByCanonicalUri(
        'https://remote.example/users/alice',
      );
      final edge = await followRepo.getEdge(
        'did:key:local',
        target!.targetId,
        FollowDirection.outbound,
      );

      expect(response.statusCode, 200);
      expect(edge!.status, FollowStatus.rejected);
    });

    test('routes Undo to follow service', () async {
      final followRepo = InMemoryFollowRepository();
      final service = _buildService(followRepo);
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
      await service.acceptFollow(
        followerDid: 'did:key:local',
        targetId: target!.targetId,
        actorDid: 'https://remote.example/users/alice',
        now: DateTime.utc(2026, 5, 4, 0, 1),
      );

      final controller = FollowInboxController(followService: service);
      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/undo/1',
        'type': 'Undo',
        'actor': 'did:key:local',
        'object': {
          'id': 'local://activities/follow/follow-2',
          'type': 'Follow',
          'actor': 'did:key:local',
          'object': 'https://remote.example/users/alice',
        },
        'published': '2026-05-04T00:02:00.000Z',
      });

      final edge = await followRepo.getEdge(
        'did:key:local',
        target.targetId,
        FollowDirection.outbound,
      );

      expect(response.statusCode, 200);
      expect(edge!.status, FollowStatus.cancelled);
    });

    test('routes valid Follow to follow service', () async {
      final followRepo = InMemoryFollowRepository();
      final service = _buildService(followRepo);
      final controller = FollowInboxController(followService: service);

      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/follow/1',
        'type': 'Follow',
        'actor': 'https://remote.example/users/alice',
        'object': 'did:key:local',
        'published': '2026-05-04T00:00:00.000Z',
      });

      final target = await followRepo.getTargetByCanonicalUri('did:key:local');
      final edge = await followRepo.getEdge(
        'https://remote.example/users/alice',
        target!.targetId,
        FollowDirection.outbound,
      );

      expect(response.statusCode, 200);
      expect(edge!.status, FollowStatus.accepted);
    });
  });
}

FollowService _buildService(InMemoryFollowRepository followRepo) {
  return FollowService(
    followRepository: followRepo,
    outboxRepository: InMemoryFollowActivityOutboxRepository(),
    boardSyncConfigRepository: InMemoryBoardSyncConfigRepository(),
    idFactory: _SequenceIds(),
  );
}

class _SequenceIds implements FollowIdFactory {
  var _next = 0;

  @override
  String next(String prefix) {
    _next += 1;
    return '$prefix-$_next';
  }
}
