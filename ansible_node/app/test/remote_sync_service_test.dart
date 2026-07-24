import 'dart:convert';

import 'package:ansible_node/services/op_signature_payload.dart';
import 'package:ansible_node/services/remote_sync_service.dart';
import 'package:ansible_node/services/self_backfill_state_store.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'RelayApiClient reads relay ops delta and maps it to activities',
    () async {
      final client = RelayApiClient(
        baseUrl: 'http://relay.local/root',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://relay.local/root/api/v1/ops/delta?cursor=7&limit=25',
          );
          return http.Response('''
          {
            "ops": [
              {
                "log_id": 9,
                "op_id": "op-1",
                "author_did": "did:plc:alice",
                "entity_type": "post",
                "entity_id": "post-1",
                "op_type": "insert",
                "payload": "eyJib2FyZElkIjoiYm9hcmQtMSIsInRocmVhZElkIjoidGhyZWFkLTEiLCJjb250ZW50IjoiaGVsbG8ifQ==",
                "signature": "${'a' * 128}",
                "public_key_hex": "${'b' * 64}",
                "received_at": "2026-05-09T12:00:00Z"
              }
            ],
            "next_cursor": 9,
            "has_more": false
          }
          ''', 200);
        }),
      );

      final delta = await client.getDelta(cursor: 7, limit: 25);

      expect(delta['nextCursor'], 9);
      expect(delta['hasMore'], isFalse);
      final activities = delta['activities'] as List<dynamic>;
      expect(activities, hasLength(1));
      expect(activities.single['logId'], 9);
      expect(activities.single['activity']['boardId'], 'board-1');
      expect(activities.single['activity']['threadId'], 'thread-1');
      expect(activities.single['activity']['payload']['content'], 'hello');
      expect(activities.single['signedOp']['signature'], 'a' * 128);
      expect(activities.single['signedOp']['publicKeyHex'], 'b' * 64);
    },
  );

  test('RelayApiClient reports an empty successful delta response', () async {
    final client = RelayApiClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async => http.Response('', 200)),
    );

    await expectLater(
      client.getDelta(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Relay delta returned an empty response',
        ),
      ),
    );
  });

  test(
    'RemoteOpSignatureVerifier verifies canonical signed op envelope',
    () async {
      late String verifiedMessage;
      final verifier = RemoteOpSignatureVerifier(
        verify:
            ({
              required publicKeyHex,
              required message,
              required signatureHex,
            }) async {
              expect(publicKeyHex, 'b' * 64);
              expect(signatureHex, 'a' * 128);
              verifiedMessage = utf8.decode(message);
              return true;
            },
      );
      final entry = _signedActivityJson(
        logId: 1,
        opId: 'op-1',
        authorDid: 'did:key:remote',
        entityType: 'post',
        entityId: 'post-1',
        opType: 'insert',
        payload: 'payload-base64',
        signature: 'a' * 128,
        publicKeyHex: 'b' * 64,
      );

      expect(await verifier.isTrusted(entry), isTrue);
      expect(
        verifiedMessage,
        OpSignaturePayload.fromFields(
          opId: 'op-1',
          authorDid: 'did:key:remote',
          entityType: 'post',
          entityId: 'post-1',
          opType: 'insert',
          payload: 'payload-base64',
        ),
      );
    },
  );

  test(
    'RemoteOpSignatureVerifier rejects op when DID is not registered in relay',
    () async {
      final verifier = RemoteOpSignatureVerifier(
        verify:
            ({
              required publicKeyHex,
              required message,
              required signatureHex,
            }) async => true,
        resolvePublicKey: (did) async => null, // DID not found
      );
      final entry = _signedActivityJson(
        logId: 1,
        opId: 'op-1',
        authorDid: 'did:key:remote',
        entityType: 'post',
        entityId: 'post-1',
        opType: 'insert',
        payload: 'payload-base64',
        signature: 'a' * 128,
        publicKeyHex: 'b' * 64,
      );

      expect(await verifier.isTrusted(entry), isFalse);
    },
  );

  test(
    'RemoteOpSignatureVerifier rejects op when relay key does not match signed key',
    () async {
      final verifier = RemoteOpSignatureVerifier(
        verify:
            ({
              required publicKeyHex,
              required message,
              required signatureHex,
            }) async => true,
        resolvePublicKey: (did) async => 'c' * 64, // different key from relay
      );
      final entry = _signedActivityJson(
        logId: 1,
        opId: 'op-1',
        authorDid: 'did:key:remote',
        entityType: 'post',
        entityId: 'post-1',
        opType: 'insert',
        payload: 'payload-base64',
        signature: 'a' * 128,
        publicKeyHex: 'b' * 64, // key used to sign — doesn't match relay
      );

      expect(await verifier.isTrusted(entry), isFalse);
    },
  );

  test(
    'RemoteOpSignatureVerifier accepts op when relay key matches signed key',
    () async {
      final verifier = RemoteOpSignatureVerifier(
        verify:
            ({
              required publicKeyHex,
              required message,
              required signatureHex,
            }) async => true,
        resolvePublicKey: (did) async => 'b' * 64, // same key as signed
      );
      final entry = _signedActivityJson(
        logId: 1,
        opId: 'op-1',
        authorDid: 'did:key:remote',
        entityType: 'post',
        entityId: 'post-1',
        opType: 'insert',
        payload: 'payload-base64',
        signature: 'a' * 128,
        publicKeyHex: 'b' * 64,
      );

      expect(await verifier.isTrusted(entry), isTrue);
    },
  );

  test(
    'RemoteOpSignatureVerifier caches resolved key for subsequent ops',
    () async {
      var resolveCalls = 0;
      final verifier = RemoteOpSignatureVerifier(
        verify:
            ({
              required publicKeyHex,
              required message,
              required signatureHex,
            }) async => true,
        resolvePublicKey: (did) async {
          resolveCalls++;
          return 'b' * 64;
        },
      );
      final entry = _signedActivityJson(
        logId: 1,
        opId: 'op-1',
        authorDid: 'did:key:remote',
        entityType: 'post',
        entityId: 'post-1',
        opType: 'insert',
        payload: 'payload-base64',
        signature: 'a' * 128,
        publicKeyHex: 'b' * 64,
      );

      await verifier.isTrusted(entry);
      await verifier.isTrusted(entry);

      expect(resolveCalls, 1); // second call uses cache
    },
  );

  test('does not fetch or apply delta when no boards are enabled', () async {
    final boardRepo = InMemoryBoardRepository();
    final threadRepo = InMemoryThreadRepository();
    final postRepo = InMemoryPostRepository();
    final remoteNodeRepo = _FakeRemoteNodeRepository();
    final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
      configs: const [],
    );
    final client = _FakeRelayApiClient();
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      syncCursor: 123,
      createdAt: DateTime.utc(2026, 5, 4),
      updatedAt: DateTime.utc(2026, 5, 4),
    );

    final service = RemoteSyncService(
      remoteNodeRepo: remoteNodeRepo,
      boardSyncConfigRepo: boardSyncConfigRepo,
      boardRepo: boardRepo,
      threadRepo: threadRepo,
      postRepo: postRepo,
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
    );

    final result = await service.syncFromNode(client, remoteNode);

    expect(result.success, isTrue);
    expect(result.activitiesProcessed, 0);
    expect(result.newCursor, 123);
    expect(client.getDeltaCalls, 0);
    expect(remoteNodeRepo.updatedCursor, isNull);
    expect(await boardRepo.list(), isEmpty);
    expect(await threadRepo.list(), isEmpty);
    expect(await postRepo.list(), isEmpty);
  });

  test(
    'keeps followed-users murmur/note and posts without board opt-in',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final contentRepo = InMemoryContentItemRepository();
      final followRepo = InMemoryFollowRepository();
      final remoteNodeRepo = _FakeRemoteNodeRepository();
      final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
        configs: const [],
      );
      final now = DateTime.utc(2026, 6, 4);

      // Follow alice (accepted user follow with a DID).
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
          followId: 'f-alice',
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

      final client = _FakeRelayApiClient(
        activities: [
          {
            'logId': 1,
            'activity': {
              'activityId': 'm1',
              'type': 'create',
              'entityType': 'murmur',
              'entityId': 'm1',
              'authorId': 'did:key:alice',
              'createdAt': '2026-06-04T09:00:00Z',
              'payload': {
                'mode': 'murmur',
                'body': 'hello',
                'visibility': 'public',
                'publishedAt': '2026-06-04T09:00:00Z',
              },
            },
          },
          {
            'logId': 2,
            'activity': {
              'activityId': 'm2',
              'type': 'create',
              'entityType': 'murmur',
              'entityId': 'm2',
              'authorId': 'did:key:bob',
              'createdAt': '2026-06-04T09:30:00Z',
              'payload': {
                'mode': 'murmur',
                'body': 'spam',
                'visibility': 'public',
              },
            },
          },
          {
            'logId': 3,
            'activity': {
              'activityId': 'p1',
              'type': 'create',
              'entityType': 'post',
              'entityId': 'p1',
              'boardId': 'board-x',
              'threadId': 'thread-x',
              'authorId': 'did:key:alice',
              'createdAt': '2026-06-04T08:00:00Z',
              'payload': {'content': 'in an unsynced board'},
            },
          },
        ],
      );
      final remoteNode = RemoteNode(
        id: 'remote-1',
        name: 'Remote',
        url: 'https://relay.example',
        syncCursor: 0,
        createdAt: now,
        updatedAt: now,
      );

      final service = RemoteSyncService(
        remoteNodeRepo: remoteNodeRepo,
        boardSyncConfigRepo: boardSyncConfigRepo,
        boardRepo: boardRepo,
        threadRepo: threadRepo,
        postRepo: postRepo,
        followRepository: followRepo,
        contentItemRepo: contentRepo,
        followerDid: 'did:key:local',
        opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      );

      final result = await service.syncFromNode(client, remoteNode);
      expect(result.success, isTrue);

      // Alice's murmur stored; bob's dropped.
      final items = await contentRepo.list();
      expect(items.map((i) => i.id), ['m1']);
      expect(items.single.mode, ContentMode.murmur);
      expect(items.single.authorDid, 'did:key:alice');

      // Alice's post stored with stub board + thread.
      expect((await postRepo.list()).map((p) => p.id), ['p1']);
      expect(await boardRepo.getById('board-x'), isNotNull);
      expect(await threadRepo.getById('thread-x'), isNotNull);
    },
  );

  test(
    'first sync replays from zero and restores content authored by local DID',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final contentRepo = InMemoryContentItemRepository();
      final remoteNodeRepo = _FakeRemoteNodeRepository();
      final backfillState = InMemorySelfBackfillStateStore();
      final client = _FakeRelayApiClient(
        activities: [
          {
            'logId': 21,
            'activity': {
              'activityId': 'self-note',
              'type': 'create',
              'entityType': 'murmur',
              'entityId': 'self-note',
              'authorId': 'did:key:local',
              'createdAt': '2026-07-21T09:00:00Z',
              'payload': {
                'mode': 'murmur',
                'body': 'my published note',
                'visibility': 'public',
              },
            },
          },
          {
            'logId': 22,
            'activity': {
              'activityId': 'someone-else',
              'type': 'create',
              'entityType': 'murmur',
              'entityId': 'someone-else',
              'authorId': 'did:key:other',
              'createdAt': '2026-07-21T10:00:00Z',
              'payload': {
                'mode': 'murmur',
                'body': 'not followed',
                'visibility': 'public',
              },
            },
          },
        ],
      );
      final remoteNode = RemoteNode(
        id: 'remote-1',
        name: 'Remote',
        url: 'https://relay.example',
        syncCursor: 23,
        createdAt: DateTime.utc(2026, 7, 21),
        updatedAt: DateTime.utc(2026, 7, 21),
      );

      final result = await RemoteSyncService(
        remoteNodeRepo: remoteNodeRepo,
        boardSyncConfigRepo: _FakeBoardSyncConfigRepository(configs: const []),
        boardRepo: boardRepo,
        threadRepo: threadRepo,
        postRepo: postRepo,
        contentItemRepo: contentRepo,
        followerDid: 'did:key:local',
        selfBackfillState: backfillState,
        opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      ).syncFromNode(client, remoteNode);

      expect(result.success, isTrue);
      expect(client.requestedCursor, isNull);
      expect((await contentRepo.list()).map((item) => item.id), ['self-note']);
      expect(backfillState.markCompleteCalls, 1);
    },
  );

  test('failed self backfill is not marked complete and retries', () async {
    final backfillState = InMemorySelfBackfillStateStore();
    final client = _ThrowingRelayApiClient();
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      syncCursor: 23,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
    );
    final service = RemoteSyncService(
      remoteNodeRepo: _FakeRemoteNodeRepository(),
      boardSyncConfigRepo: _FakeBoardSyncConfigRepository(configs: const []),
      boardRepo: InMemoryBoardRepository(),
      threadRepo: InMemoryThreadRepository(),
      postRepo: InMemoryPostRepository(),
      contentItemRepo: InMemoryContentItemRepository(),
      followerDid: 'did:key:local',
      selfBackfillState: backfillState,
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
    );

    expect((await service.syncFromNode(client, remoteNode)).success, isFalse);
    expect((await service.syncFromNode(client, remoteNode)).success, isFalse);
    expect(client.getDeltaCalls, 2);
    expect(client.requestedCursors, [null, null]);
    expect(backfillState.markCompleteCalls, 0);
  });

  test('completed self backfill resumes from the normal node cursor', () async {
    final client = _FakeRelayApiClient(activities: const []);
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      syncCursor: 23,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
    );

    final result = await RemoteSyncService(
      remoteNodeRepo: _FakeRemoteNodeRepository(),
      boardSyncConfigRepo: _FakeBoardSyncConfigRepository(configs: const []),
      boardRepo: InMemoryBoardRepository(),
      threadRepo: InMemoryThreadRepository(),
      postRepo: InMemoryPostRepository(),
      contentItemRepo: InMemoryContentItemRepository(),
      followerDid: 'did:key:local',
      selfBackfillState: InMemorySelfBackfillStateStore(complete: true),
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
    ).syncFromNode(client, remoteNode, requireBoardSyncConfig: false);

    expect(result.success, isTrue);
    expect(client.requestedCursor, 23);
  });

  test(
    'does NOT trust a peer-asserted reputation tier (fail closed)',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final reputationRepo = InMemoryDidReputationRepository();
      final remoteNodeRepo = _FakeRemoteNodeRepository();
      final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
        configs: const [],
      );
      final now = DateTime.utc(2026, 6, 5);

      final client = _FakeRelayApiClient(
        activities: [
          {
            'logId': 1,
            'signedOp': {
              'opId': 'op-1',
              'authorDid': 'did:key:alice',
              'entityType': 'post',
              'entityId': 'post-1',
              'opType': 'insert',
              'payload': 'x',
              'signature': 'a' * 128,
              'publicKeyHex': 'b' * 64,
              'reputationTier': 'verified_human',
            },
            'activity': {
              'activityId': 'op-1',
              'type': 'create',
              'entityType': 'post',
              'entityId': 'post-1',
              'boardId': 'board-1',
              'threadId': 'thread-1',
              'authorId': 'did:key:alice',
              'createdAt': '2026-06-05T00:00:00Z',
              'payload': {'content': 'hi'},
            },
          },
        ],
      );
      final remoteNode = RemoteNode(
        id: 'remote-1',
        name: 'Remote',
        url: 'https://relay.example',
        syncCursor: 0,
        createdAt: now,
        updatedAt: now,
      );

      await RemoteSyncService(
        remoteNodeRepo: remoteNodeRepo,
        boardSyncConfigRepo: boardSyncConfigRepo,
        boardRepo: boardRepo,
        threadRepo: threadRepo,
        postRepo: postRepo,
        didReputationRepo: reputationRepo,
        opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      ).syncFromNode(client, remoteNode, requireBoardSyncConfig: false);

      // The op claims verified_human, but that field is unsigned and relay-
      // stamped — it must never elevate the author. Fail closed.
      expect(
        await reputationRepo.tierFor('did:key:alice'),
        isNot('verified_human'),
      );
    },
  );

  test('skips unsigned relay delta entries before applying them', () async {
    final boardRepo = InMemoryBoardRepository();
    final threadRepo = InMemoryThreadRepository();
    final postRepo = InMemoryPostRepository();
    final remoteNodeRepo = _FakeRemoteNodeRepository();
    final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
      configs: const [],
    );
    final client = _FakeRelayApiClient(
      activities: [
        {
          'logId': 1,
          'activity': {
            'activityId': 'activity-board-1',
            'type': 'create',
            'entityType': 'board',
            'entityId': 'board-1',
            'boardId': 'board-1',
            'authorId': 'did:key:remote',
            'createdAt': '2026-05-04T00:00:00Z',
            'payload': {'slug': 'general', 'title': 'General'},
          },
        },
      ],
    );
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      syncCursor: 0,
      createdAt: DateTime.utc(2026, 5, 4),
      updatedAt: DateTime.utc(2026, 5, 4),
    );

    final result = await RemoteSyncService(
      remoteNodeRepo: remoteNodeRepo,
      boardSyncConfigRepo: boardSyncConfigRepo,
      boardRepo: boardRepo,
      threadRepo: threadRepo,
      postRepo: postRepo,
    ).syncFromNode(client, remoteNode, requireBoardSyncConfig: false);

    expect(result.success, isTrue);
    expect(result.activitiesProcessed, 0);
    expect(await boardRepo.list(), isEmpty);
  });

  test('foreground refresh applies relay feed without board opt-in', () async {
    final boardRepo = InMemoryBoardRepository();
    final threadRepo = InMemoryThreadRepository();
    final postRepo = InMemoryPostRepository();
    final remoteNodeRepo = _FakeRemoteNodeRepository();
    final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
      configs: const [],
    );
    final client = _FakeRelayApiClient(
      activities: [
        {
          'logId': 1,
          'activity': {
            'activityId': 'activity-board-1',
            'type': 'create',
            'entityType': 'board',
            'entityId': 'board-1',
            'boardId': 'board-1',
            'authorId': 'did:key:remote',
            'createdAt': '2026-05-04T00:00:00Z',
            'payload': {'slug': 'general', 'title': 'General'},
          },
        },
        {
          'logId': 2,
          'activity': {
            'activityId': 'activity-thread-1',
            'type': 'create',
            'entityType': 'thread',
            'entityId': 'thread-1',
            'boardId': 'board-1',
            'authorId': 'did:key:remote',
            'createdAt': '2026-05-04T00:01:00Z',
            'payload': {'title': 'Relay discussion'},
          },
        },
        _postActivityJson(
          logId: 3,
          postId: 'post-1',
          createdAt: '2026-05-04T00:02:00Z',
        ),
      ],
    );
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      syncCursor: 0,
      createdAt: DateTime.utc(2026, 5, 4),
      updatedAt: DateTime.utc(2026, 5, 4),
    );

    final service = RemoteSyncService(
      remoteNodeRepo: remoteNodeRepo,
      boardSyncConfigRepo: boardSyncConfigRepo,
      boardRepo: boardRepo,
      threadRepo: threadRepo,
      postRepo: postRepo,
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
    );

    final result = await service.syncFromNode(
      client,
      remoteNode,
      requireBoardSyncConfig: false,
    );

    expect(result.success, isTrue);
    expect(result.activitiesProcessed, 3);
    expect(remoteNodeRepo.updatedCursor, 124);
    expect((await boardRepo.list()).single.title, 'General');
    expect((await threadRepo.list()).single.title, 'Relay discussion');
    expect((await postRepo.list()).single.content, 'post-1');
  });

  test(
    'pull sync uses hosted board subscriptions when legacy config is absent',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final hostedBoards = InMemoryHostedBoardRepository();
      final remoteNodeRepo = _FakeRemoteNodeRepository();
      final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
        configs: const [],
      );
      final now = DateTime.utc(2026, 5, 10);
      await hostedBoards.upsertProjection(
        HostedBoardProjection(
          localBoardId: 'local-general',
          forumHostId: 'remote-1',
          hostedBoardId: 'hosted-general',
          canonicalBoardUri: 'https://relay.example/boards/general',
          remoteSlug: 'general',
          localSlug: 'general-remote',
          title: 'Remote General',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await hostedBoards.upsertSubscription(
        BoardSubscription(
          subscriptionId: 'remote-1_hosted-general',
          forumHostId: 'remote-1',
          hostedBoardId: 'hosted-general',
          localBoardId: 'local-general',
          readEnabled: true,
          writeEnabled: true,
          syncCursor: 0,
          retentionDays: 45,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final client = _FakeRelayApiClient(
        activities: [
          {
            'logId': 1,
            'activity': {
              'activityId': 'activity-board',
              'type': 'create',
              'entityType': 'board',
              'entityId': 'hosted-general',
              'boardId': 'hosted-general',
              'authorId': 'did:key:remote',
              'createdAt': '2026-05-10T00:00:00Z',
              'payload': {'slug': 'general', 'title': 'Remote General'},
            },
          },
          {
            'logId': 2,
            'activity': {
              'activityId': 'activity-thread',
              'type': 'create',
              'entityType': 'thread',
              'entityId': 'thread-1',
              'boardId': 'hosted-general',
              'authorId': 'did:key:remote',
              'createdAt': '2026-05-10T00:01:00Z',
              'payload': {'title': 'Hosted discussion'},
            },
          },
          {
            'logId': 3,
            'activity': {
              'activityId': 'activity-other',
              'type': 'create',
              'entityType': 'thread',
              'entityId': 'thread-other',
              'boardId': 'other-board',
              'authorId': 'did:key:remote',
              'createdAt': '2026-05-10T00:02:00Z',
              'payload': {'title': 'Skipped discussion'},
            },
          },
        ],
      );
      final remoteNode = RemoteNode(
        id: 'remote-1',
        name: 'Remote',
        url: 'https://relay.example',
        syncCursor: 123,
        createdAt: now,
        updatedAt: now,
      );

      final result = await RemoteSyncService(
        remoteNodeRepo: remoteNodeRepo,
        boardSyncConfigRepo: boardSyncConfigRepo,
        hostedBoardRepo: hostedBoards,
        boardRepo: boardRepo,
        threadRepo: threadRepo,
        postRepo: postRepo,
        opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
        now: () => now,
      ).syncFromNode(client, remoteNode);

      final boards = await boardRepo.list();
      final threads = await threadRepo.list();
      final subscriptions = await hostedBoards.listSubscriptions(
        forumHostId: 'remote-1',
      );
      expect(result.success, isTrue);
      expect(result.activitiesProcessed, 2);
      expect(boards.single.id, 'local-general');
      expect(boards.single.slug, 'general-remote');
      expect(threads.single.boardId, 'local-general');
      expect(threads.single.title, 'Hosted discussion');
      expect(subscriptions.single.syncCursor, 124);
      expect(client.requestedCursor, isNull);
    },
  );

  test(
    'protected board uses scoped delta and advances only its cursor',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final hostedBoards = InMemoryHostedBoardRepository();
      final now = DateTime.utc(2026, 7, 22);
      await boardRepo.create(
        Board(
          id: 'local-members',
          slug: 'members',
          title: 'Members',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await hostedBoards.upsertProjection(
        HostedBoardProjection(
          localBoardId: 'local-members',
          forumHostId: 'remote-1',
          hostedBoardId: 'members',
          canonicalBoardUri: 'https://relay.example/boards/members',
          remoteSlug: 'members',
          localSlug: 'members',
          title: 'Members',
          accessPolicy: const {
            'read': {'requirement': 'party-member'},
          },
          contentVisibility: 'host_visible',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await hostedBoards.upsertSubscription(
        BoardSubscription(
          subscriptionId: 'remote-1_members',
          forumHostId: 'remote-1',
          hostedBoardId: 'members',
          localBoardId: 'local-members',
          readEnabled: true,
          writeEnabled: true,
          syncCursor: 40,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final client = _FakeRelayApiClient(
        boardActivities: [
          {
            'logId': 42,
            'activity': {
              'activityId': 'thread-42',
              'type': 'create',
              'entityType': 'thread',
              'entityId': 'thread-42',
              'boardId': 'members',
              'authorId': 'did:key:member',
              'createdAt': '2026-07-22T00:00:00Z',
              'payload': {'title': 'Private discussion'},
            },
          },
        ],
      );
      var authorizationCalls = 0;
      final result =
          await RemoteSyncService(
            remoteNodeRepo: _FakeRemoteNodeRepository(),
            boardSyncConfigRepo: _FakeBoardSyncConfigRepository(
              configs: const [],
            ),
            hostedBoardRepo: hostedBoards,
            boardRepo: boardRepo,
            threadRepo: threadRepo,
            postRepo: postRepo,
            opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
            authorizeBoardRead: (board, uri) async {
              authorizationCalls++;
              expect(board.hostedBoardId, 'members');
              expect(uri.path, '/api/v1/forum-host/boards/members/ops/delta');
              return const {'x-elix-board-capability': 'capability'};
            },
            now: () => now,
          ).syncFromNode(
            client,
            RemoteNode(
              id: 'remote-1',
              name: 'Remote',
              url: 'https://relay.example',
              syncCursor: 100,
              createdAt: now,
              updatedAt: now,
            ),
          );

      expect(result.success, isTrue);
      expect(client.getDeltaCalls, 1);
      expect(client.getBoardDeltaCalls, 1);
      expect(client.requestedBoardCursor, 40);
      expect(authorizationCalls, 1);
      expect((await threadRepo.list()).single.boardId, 'local-members');
      expect((await hostedBoards.listSubscriptions()).single.syncCursor, 142);
    },
  );

  test('pull routes a thread whose boardId has a foreign install prefix to the '
      'local board via the hosted_board_id suffix', () async {
    final boardRepo = InMemoryBoardRepository();
    final threadRepo = InMemoryThreadRepository();
    final postRepo = InMemoryPostRepository();
    final hostedBoards = InMemoryHostedBoardRepository();
    final remoteNodeRepo = _FakeRemoteNodeRepository();
    final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
      configs: const [],
    );
    final now = DateTime.utc(2026, 5, 10);
    await boardRepo.create(
      Board(
        id: 'local-fifa',
        slug: 'fifa2026',
        title: 'FIFA2026',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await hostedBoards.upsertProjection(
      HostedBoardProjection(
        localBoardId: 'local-fifa',
        forumHostId: 'remote-1',
        hostedBoardId: 'fifa2026',
        canonicalBoardUri: 'https://relay.example/boards/fifa2026',
        remoteSlug: 'fifa2026',
        localSlug: 'fifa2026',
        title: 'FIFA2026',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await hostedBoards.upsertSubscription(
      BoardSubscription(
        subscriptionId: 'remote-1_fifa2026',
        forumHostId: 'remote-1',
        hostedBoardId: 'fifa2026',
        localBoardId: 'local-fifa',
        readEnabled: true,
        writeEnabled: true,
        syncCursor: 0,
        retentionDays: 45,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await threadRepo.create(
      Thread(
        id: 'thread-x',
        boardId: '',
        title: '不見了',
        authorId: 'did:plc:remote',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final client = _FakeRelayApiClient(
      activities: [
        {
          'logId': 1,
          'activity': {
            'activityId': 'a-thread',
            'type': 'create',
            'entityType': 'thread',
            'entityId': 'thread-x',
            // Composite boardId minted by a *different* install (its forum-host
            // node id is a timestamp); only the hosted_board_id suffix is stable.
            'boardId': '1781793146433_fifa2026',
            'authorId': 'did:plc:remote',
            'createdAt': '2026-05-10T00:01:00Z',
            'payload': {'title': '不見了'},
          },
        },
      ],
    );
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      createdAt: now,
      updatedAt: now,
    );

    final result = await RemoteSyncService(
      remoteNodeRepo: remoteNodeRepo,
      boardSyncConfigRepo: boardSyncConfigRepo,
      hostedBoardRepo: hostedBoards,
      boardRepo: boardRepo,
      threadRepo: threadRepo,
      postRepo: postRepo,
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      now: () => now,
    ).syncFromNode(client, remoteNode);

    final threads = await threadRepo.list();
    expect(result.success, isTrue);
    expect(threads.single.boardId, 'local-fifa');
    expect(threads.single.title, '不見了');
  });

  test(
    'remote board slug conflict keeps both boards with unique slugs',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final remoteNodeRepo = _FakeRemoteNodeRepository();
      final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
        configs: const [],
      );
      final now = DateTime.utc(2026, 5, 10);
      await boardRepo.create(
        Board(
          id: 'local-board',
          slug: 'general',
          title: 'Local General',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final client = _FakeRelayApiClient(
        activities: [
          {
            'logId': 1,
            'activity': {
              'activityId': 'activity-remote-board',
              'type': 'create',
              'entityType': 'board',
              'entityId': 'remote-board',
              'boardId': 'remote-board',
              'authorId': 'did:key:remote',
              'createdAt': '2026-05-10T00:00:00Z',
              'payload': {'slug': 'general', 'title': 'Remote General'},
            },
          },
        ],
      );
      final remoteNode = RemoteNode(
        id: 'remote-1',
        name: 'Remote',
        url: 'https://relay.example',
        createdAt: now,
        updatedAt: now,
      );

      final result = await RemoteSyncService(
        remoteNodeRepo: remoteNodeRepo,
        boardSyncConfigRepo: boardSyncConfigRepo,
        boardRepo: boardRepo,
        threadRepo: threadRepo,
        postRepo: postRepo,
        opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      ).syncFromNode(client, remoteNode, requireBoardSyncConfig: false);

      final boards = await boardRepo.list();
      final local = boards.singleWhere((board) => board.id == 'local-board');
      final remote = boards.singleWhere((board) => board.id == 'remote-board');
      expect(result.success, isTrue);
      expect(local.slug, 'general');
      expect(local.title, 'Local General');
      expect(remote.slug, 'general-remote-board');
      expect(remote.title, 'Remote General');
    },
  );

  test('skips posts outside board retention window', () async {
    final boardRepo = InMemoryBoardRepository();
    final threadRepo = InMemoryThreadRepository();
    final postRepo = InMemoryPostRepository();
    final remoteNodeRepo = _FakeRemoteNodeRepository();
    final now = DateTime.utc(2026, 5, 4);
    final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
      configs: [
        BoardSyncConfig(
          id: 'remote-1_board-1',
          remoteNodeId: 'remote-1',
          boardId: 'board-1',
          syncEnabled: true,
          retentionDays: 30,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final client = _FakeRelayApiClient(
      activities: [
        _postActivityJson(
          logId: 1,
          postId: 'post-old',
          createdAt: '2026-03-01T00:00:00Z',
        ),
        _postActivityJson(
          logId: 2,
          postId: 'post-recent',
          createdAt: '2026-05-01T00:00:00Z',
        ),
      ],
    );
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      createdAt: now,
      updatedAt: now,
    );

    final service = RemoteSyncService(
      remoteNodeRepo: remoteNodeRepo,
      boardSyncConfigRepo: boardSyncConfigRepo,
      boardRepo: boardRepo,
      threadRepo: threadRepo,
      postRepo: postRepo,
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      now: () => now,
    );

    final result = await service.syncFromNode(client, remoteNode);
    final posts = await postRepo.list();

    expect(result.success, isTrue);
    expect(result.activitiesProcessed, 1);
    expect(posts.map((post) => post.id), ['post-recent']);
  });

  test('retention window never prunes existing local posts', () async {
    final boardRepo = InMemoryBoardRepository();
    final threadRepo = InMemoryThreadRepository();
    final postRepo = InMemoryPostRepository();
    final remoteNodeRepo = _FakeRemoteNodeRepository();
    final now = DateTime.utc(2026, 5, 4);
    await postRepo.create(
      Post(
        id: 'post-old',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: 'did:key:local',
        content: 'old',
        createdAt: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 3, 1),
        lastEditAt: DateTime.utc(2026, 3, 1),
      ),
    );
    await postRepo.create(
      Post(
        id: 'post-recent',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: 'did:key:local',
        content: 'recent',
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
        lastEditAt: DateTime.utc(2026, 5, 1),
      ),
    );
    final boardSyncConfigRepo = _FakeBoardSyncConfigRepository(
      configs: [
        BoardSyncConfig(
          id: 'remote-1_board-1',
          remoteNodeId: 'remote-1',
          boardId: 'board-1',
          syncEnabled: true,
          retentionDays: 30,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final client = _FakeRelayApiClient(activities: const []);
    final remoteNode = RemoteNode(
      id: 'remote-1',
      name: 'Remote',
      url: 'https://relay.example',
      createdAt: now,
      updatedAt: now,
    );

    final service = RemoteSyncService(
      remoteNodeRepo: remoteNodeRepo,
      boardSyncConfigRepo: boardSyncConfigRepo,
      boardRepo: boardRepo,
      threadRepo: threadRepo,
      postRepo: postRepo,
      opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
      now: () => now,
    );

    final result = await service.syncFromNode(client, remoteNode);
    final posts = await postRepo.list();

    expect(result.success, isTrue);
    expect(
      posts.map((post) => post.id),
      containsAll(['post-old', 'post-recent']),
    );
  });

  test(
    'remote delete ops create scoped tombstones and preserve local canonical data',
    () async {
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final contentRepo = InMemoryContentItemRepository();
      final tombstones = InMemoryRemoteTombstoneRepository();
      final now = DateTime.utc(2026, 7, 17);
      await boardRepo.create(
        Board(
          id: 'board-1',
          slug: 'local',
          title: 'Local',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await threadRepo.create(
        Thread(
          id: 'thread-1',
          boardId: 'board-1',
          title: 'Kept',
          authorId: 'did:elix:alice',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await postRepo.create(
        Post(
          id: 'post-1',
          threadId: 'thread-1',
          boardId: 'board-1',
          authorId: 'did:elix:alice',
          content: 'Kept locally',
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
        ),
      );
      await contentRepo.create(
        ContentItem(
          id: 'note-1',
          authorDid: 'did:elix:alice',
          mode: ContentMode.note,
          body: 'Local note',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          localOnly: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
      Map<String, dynamic> deletion(
        String type,
        String id, {
        String? boardId,
        String? threadId,
      }) => {
        'logId': id.hashCode,
        'activity': {
          'activityId': 'delete-$id',
          'type': 'delete',
          'entityType': type,
          'entityId': id,
          'boardId': boardId,
          'threadId': threadId,
          'authorId': 'did:elix:alice',
          'createdAt': now.toIso8601String(),
          'payload': <String, dynamic>{},
        },
      };
      final client = _FakeRelayApiClient(
        activities: [
          deletion('board', 'board-1', boardId: 'board-1'),
          deletion('thread', 'thread-1', boardId: 'board-1'),
          deletion('post', 'post-1', boardId: 'board-1', threadId: 'thread-1'),
          deletion('note', 'note-1'),
          deletion('account', 'did:elix:alice'),
        ],
      );
      final result =
          await RemoteSyncService(
            remoteNodeRepo: _FakeRemoteNodeRepository(),
            boardSyncConfigRepo: _FakeBoardSyncConfigRepository(
              configs: const [],
            ),
            boardRepo: boardRepo,
            threadRepo: threadRepo,
            postRepo: postRepo,
            contentItemRepo: contentRepo,
            remoteTombstoneRepository: tombstones,
            opSignatureVerifier: _TrustingRemoteOpSignatureVerifier(),
            now: () => now,
          ).syncFromNode(
            client,
            RemoteNode(
              id: 'relay-1',
              name: 'Relay',
              url: 'https://relay.example',
              createdAt: now,
              updatedAt: now,
            ),
            requireBoardSyncConfig: false,
          );

      expect(result.success, isTrue);
      expect(await boardRepo.getById('board-1'), isNotNull);
      expect(await threadRepo.getById('thread-1'), isNotNull);
      expect(await postRepo.getById('post-1'), isNotNull);
      expect(await contentRepo.getById('note-1'), isNotNull);
      expect(await tombstones.list(sourceNodeId: 'relay-1'), hasLength(5));
    },
  );
}

class _FakeRelayApiClient extends RelayApiClient {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> boardActivities;
  int getDeltaCalls = 0;
  int getBoardDeltaCalls = 0;
  int? requestedCursor;
  int? requestedBoardCursor;

  _FakeRelayApiClient({
    List<Map<String, dynamic>>? activities,
    this.boardActivities = const [],
  }) : activities =
           activities ??
           [
             {
               'logId': 1,
               'activity': {
                 'activityId': 'activity-board-1',
                 'type': 'create',
                 'entityType': 'board',
                 'entityId': 'board-1',
                 'boardId': 'board-1',
                 'authorId': 'did:key:remote',
                 'createdAt': '2026-05-04T00:00:00Z',
                 'payload': {'slug': 'general', 'title': 'General'},
               },
             },
           ],
       super(baseUrl: 'https://relay.example');

  @override
  Future<Map<String, dynamic>> getDelta({int? cursor, int limit = 100}) async {
    getDeltaCalls += 1;
    requestedCursor = cursor;
    return {'activities': activities, 'nextCursor': 124, 'hasMore': false};
  }

  @override
  Future<Map<String, dynamic>> getBoardDelta({
    required String boardId,
    required Map<String, String> proofHeaders,
    int? cursor,
    int limit = 100,
  }) async {
    getBoardDeltaCalls += 1;
    requestedBoardCursor = cursor;
    expect(boardId, 'members');
    expect(proofHeaders['x-elix-board-capability'], 'capability');
    return {'activities': boardActivities, 'nextCursor': 142, 'hasMore': false};
  }
}

class _ThrowingRelayApiClient extends RelayApiClient {
  _ThrowingRelayApiClient() : super(baseUrl: 'https://relay.example');

  int getDeltaCalls = 0;
  final List<int?> requestedCursors = [];

  @override
  Future<Map<String, dynamic>> getDelta({int? cursor, int limit = 100}) async {
    getDeltaCalls++;
    requestedCursors.add(cursor);
    throw StateError('offline');
  }
}

class _TrustingRemoteOpSignatureVerifier extends RemoteOpSignatureVerifier {
  @override
  Future<bool> isTrusted(Map<String, dynamic> entry) async => true;
}

class _FakeRemoteNodeRepository implements RemoteNodeRepository {
  int? updatedCursor;

  @override
  Future<void> create(RemoteNode node) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<RemoteNode?> getActive() async => null;

  @override
  Future<RemoteNode?> getById(String id) async => null;

  @override
  Future<List<RemoteNode>> list() async => const [];

  @override
  Future<void> update(RemoteNode node) async {}

  @override
  Future<void> updateSyncCursor(
    String id,
    int cursor,
    DateTime syncTime,
  ) async {
    updatedCursor = cursor;
  }
}

class _FakeBoardSyncConfigRepository implements BoardSyncConfigRepository {
  final List<BoardSyncConfig> configs;

  _FakeBoardSyncConfigRepository({required this.configs});

  @override
  Future<void> create(BoardSyncConfig config) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<String>> getEnabledBoardIds(String remoteNodeId) async {
    return configs
        .where(
          (config) => config.remoteNodeId == remoteNodeId && config.syncEnabled,
        )
        .map((config) => config.boardId)
        .toList();
  }

  @override
  Future<BoardSyncConfig?> getById(String id) async => null;

  @override
  Future<BoardSyncConfig?> getByRemoteAndBoard(
    String remoteNodeId,
    String boardId,
  ) async {
    return null;
  }

  @override
  Future<List<BoardSyncConfig>> listByRemote(String remoteNodeId) async {
    return configs
        .where((config) => config.remoteNodeId == remoteNodeId)
        .toList();
  }

  @override
  Future<List<BoardSyncConfig>> listEnabledByRemote(String remoteNodeId) async {
    return configs
        .where(
          (config) => config.remoteNodeId == remoteNodeId && config.syncEnabled,
        )
        .toList();
  }

  @override
  Future<void> toggleSync(
    String remoteNodeId,
    String boardId,
    bool enabled,
  ) async {}

  @override
  Future<void> update(BoardSyncConfig config) async {}
}

Map<String, dynamic> _signedActivityJson({
  required int logId,
  required String opId,
  required String authorDid,
  required String entityType,
  required String entityId,
  required String opType,
  required String payload,
  required String signature,
  required String publicKeyHex,
}) {
  return {
    'logId': logId,
    'signedOp': {
      'opId': opId,
      'authorDid': authorDid,
      'entityType': entityType,
      'entityId': entityId,
      'opType': opType,
      'payload': payload,
      'signature': signature,
      'publicKeyHex': publicKeyHex,
    },
    'activity': {
      'activityId': opId,
      'type': 'create',
      'entityType': entityType,
      'entityId': entityId,
      'boardId': 'board-1',
      'threadId': 'thread-1',
      'authorId': authorDid,
      'createdAt': '2026-05-04T00:00:00Z',
      'payload': {'content': 'hello'},
    },
  };
}

Map<String, dynamic> _postActivityJson({
  required int logId,
  required String postId,
  required String createdAt,
}) {
  return {
    'logId': logId,
    'activity': {
      'activityId': 'activity-$postId',
      'type': 'create',
      'entityType': 'post',
      'entityId': postId,
      'boardId': 'board-1',
      'threadId': 'thread-1',
      'authorId': 'did:key:remote',
      'createdAt': createdAt,
      'payload': {'content': postId},
    },
  };
}
