import 'dart:convert';

import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_node/services/host_moderation_sync_service.dart';
import 'package:ansible_node/services/notification_projector.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const localDid = 'did:plc:local-user';
  const otherDid = 'did:plc:someone-else';

  final now = DateTime.utc(2026, 6, 13);

  RemoteNode node() => RemoteNode(
    id: 'host-1',
    name: 'Host',
    url: 'https://relay.example',
    createdAt: now,
    updatedAt: now,
  );

  late InMemoryHostedBoardRepository hostedBoards;
  late InMemoryHostModerationStateRepository moderationRepo;
  late InMemoryThreadRepository threads;
  late InMemoryPostRepository posts;
  late InMemoryNotificationRepository notifications;
  late List<String> requestedPaths;

  setUp(() async {
    hostedBoards = InMemoryHostedBoardRepository();
    moderationRepo = InMemoryHostModerationStateRepository();
    threads = InMemoryThreadRepository();
    posts = InMemoryPostRepository();
    notifications = InMemoryNotificationRepository();
    requestedPaths = [];

    await hostedBoards.upsertProjection(
      HostedBoardProjection(
        localBoardId: 'local-board-1',
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        canonicalBoardUri: 'https://relay.example/boards/hosted-1',
        remoteSlug: 'general',
        localSlug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await hostedBoards.upsertSubscription(
      BoardSubscription(
        subscriptionId: 'sub-1',
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        localBoardId: 'local-board-1',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  HostModerationSyncService service(
    Map<String, Map<String, Object?>> stateByHostedBoardId,
  ) {
    return HostModerationSyncService(
      moderationRepo: moderationRepo,
      hostedBoardRepo: hostedBoards,
      threadRepo: threads,
      postRepo: posts,
      notificationProjector: NotificationProjector(
        notifications: notifications,
        localDid: localDid,
        threadRepository: threads,
        postRepository: posts,
      ),
      localDid: localDid,
      clientFactory: (baseUrl) => ForumHostClient(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          final match = RegExp(
            r'^/api/v1/forum-host/boards/(.+)/moderation-state$',
          ).firstMatch(request.url.path);
          final state = match == null
              ? null
              : stateByHostedBoardId[match.group(1)];
          if (state == null) {
            return http.Response(jsonEncode({'error': 'unknown_board'}), 404);
          }
          return http.Response(jsonEncode(state), 200);
        }),
      ),
    );
  }

  Future<void> seedPost({required String id, required String authorId}) {
    return posts.create(
      Post(
        id: id,
        threadId: 'thread-1',
        boardId: 'local-board-1',
        authorId: authorId,
        content: 'hello',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      ),
    );
  }

  Future<void> seedThread({required String id, required String authorId}) {
    return threads.create(
      Thread(
        id: id,
        boardId: 'local-board-1',
        title: 'A thread',
        authorId: authorId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('snapshot-applies the host state under the local board id', () async {
    await service({
      'hosted-1': {
        'removed_posts': [
          {'target_ref': 'post-1', 'reason_code': 'spam'},
        ],
        'locked_threads': [
          {'thread_id': 'thread-1', 'reason_code': 'off_topic'},
        ],
      },
    }).syncForNode(node());

    expect(requestedPaths, [
      '/api/v1/forum-host/boards/hosted-1/moderation-state',
    ]);
    final stored = await moderationRepo.listForBoard('local-board-1');
    expect(stored, hasLength(2));
    final removal = await moderationRepo.entryFor('post', 'post-1');
    expect(removal!.action, 'removed');
    expect(removal.reasonCode, 'spam');
    final lock = await moderationRepo.entryFor('thread', 'thread-1');
    expect(lock!.action, 'locked');
    expect(lock.reasonCode, 'off_topic');
  });

  test('a fetch failure never breaks sync and keeps the old snapshot',
      () async {
    await moderationRepo.replaceForBoard('local-board-1', [
      HostModerationState(
        localBoardId: 'local-board-1',
        targetKind: 'post',
        targetRef: 'post-1',
        action: 'removed',
        reasonCode: 'spam',
        updatedAt: now,
      ),
    ]);

    // 404 for every board: syncForNode must complete without throwing.
    await service(const {}).syncForNode(node());

    expect(await moderationRepo.listForBoard('local-board-1'), hasLength(1));
  });

  test('new entry on my post emits a moderation_outcome notification',
      () async {
    await seedThread(id: 'thread-1', authorId: otherDid);
    await seedPost(id: 'post-1', authorId: localDid);

    await service({
      'hosted-1': {
        'removed_posts': [
          {'target_ref': 'post-1', 'reason_code': 'harassment'},
        ],
        'locked_threads': const [],
      },
    }).syncForNode(node());

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.moderationOutcome);
    expect(all.single.targetRef, 'post-1');
    expect(all.single.postId, 'post-1');
    expect(all.single.threadId, 'thread-1');
    expect(all.single.boardId, 'local-board-1');
    expect(all.single.dedupKey, 'moderation:removed:post-1');
  });

  test('a lock on my thread emits a moderation_outcome notification',
      () async {
    await seedThread(id: 'thread-1', authorId: localDid);

    await service({
      'hosted-1': {
        'removed_posts': const [],
        'locked_threads': [
          {'thread_id': 'thread-1', 'reason_code': 'off_topic'},
        ],
      },
    }).syncForNode(node());

    final all = await notifications.list();
    expect(all, hasLength(1));
    expect(all.single.type, NotificationType.moderationOutcome);
    expect(all.single.threadId, 'thread-1');
    expect(all.single.dedupKey, 'moderation:locked:thread-1');
  });

  test('moderation of other people content never notifies', () async {
    await seedThread(id: 'thread-1', authorId: otherDid);
    await seedPost(id: 'post-1', authorId: otherDid);

    await service({
      'hosted-1': {
        'removed_posts': [
          {'target_ref': 'post-1', 'reason_code': 'spam'},
        ],
        'locked_threads': [
          {'thread_id': 'thread-1', 'reason_code': 'spam'},
        ],
      },
    }).syncForNode(node());

    expect(await notifications.list(), isEmpty);
  });

  test('re-applied snapshots never duplicate notifications', () async {
    await seedThread(id: 'thread-1', authorId: otherDid);
    await seedPost(id: 'post-1', authorId: localDid);

    final stateService = service({
      'hosted-1': {
        'removed_posts': [
          {'target_ref': 'post-1', 'reason_code': 'spam'},
        ],
        'locked_threads': const [],
      },
    });
    await stateService.syncForNode(node());
    await stateService.syncForNode(node());

    expect(await notifications.list(), hasLength(1));
  });
}
