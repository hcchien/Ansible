import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/services/remote_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      now: () => now,
    );

    final result = await service.syncFromNode(client, remoteNode);
    final posts = await postRepo.list();

    expect(result.success, isTrue);
    expect(result.activitiesProcessed, 1);
    expect(posts.map((post) => post.id), ['post-recent']);
  });

  test('prunes retained board posts older than retention window', () async {
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
      now: () => now,
    );

    final result = await service.syncFromNode(client, remoteNode);
    final posts = await postRepo.list();

    expect(result.success, isTrue);
    expect(posts.map((post) => post.id), ['post-recent']);
  });
}

class _FakeRelayApiClient extends RelayApiClient {
  final List<Map<String, dynamic>> activities;
  int getDeltaCalls = 0;

  _FakeRelayApiClient({List<Map<String, dynamic>>? activities})
    : activities =
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
    return {'activities': activities, 'nextCursor': 124, 'hasMore': false};
  }
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
