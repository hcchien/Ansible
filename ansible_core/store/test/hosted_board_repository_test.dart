import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('hosted board repositories', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('drift preserves host-owned board identity', () async {
      await _exercisesHostedBoardRepository(DriftHostedBoardRepository(db));
    });

    test('in-memory preserves host-owned board identity', () async {
      await _exercisesHostedBoardRepository(InMemoryHostedBoardRepository());
    });
  });
}

Future<void> _exercisesHostedBoardRepository(
  HostedBoardRepository repository,
) async {
  final now = DateTime.utc(2026, 5, 10);

  await repository.upsertProjection(
    HostedBoardProjection(
      localBoardId: 'local-general',
      forumHostId: 'host-1',
      hostedBoardId: 'remote-general',
      canonicalBoardUri: 'https://forum.example/boards/remote-general',
      remoteSlug: 'general',
      localSlug: 'general',
      title: 'General',
      description: 'Host-owned discussion board',
      permissions: const {'read': true, 'write': true},
      lastSeenCursor: 0,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final projection = await repository.getProjection('host-1', 'remote-general');
  expect(
    projection!.canonicalBoardUri,
    'https://forum.example/boards/remote-general',
  );
  expect(projection.permissions['write'], isTrue);

  await repository.upsertProjection(
    HostedBoardProjection(
      localBoardId: 'local-general-host-2',
      forumHostId: 'host-2',
      hostedBoardId: 'remote-general',
      canonicalBoardUri: 'https://forum-two.example/boards/remote-general',
      remoteSlug: 'general',
      localSlug: 'general-host-2',
      title: 'General',
      permissions: const {'read': true, 'write': false},
      lastSeenCursor: 7,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final projections = await repository.listProjections();
  expect(
    projections.map((board) => board.forumHostId),
    containsAll(['host-1', 'host-2']),
  );
  expect(
    projections.map((board) => board.canonicalBoardUri),
    containsAll([
      'https://forum.example/boards/remote-general',
      'https://forum-two.example/boards/remote-general',
    ]),
  );

  await repository.upsertSubscription(
    BoardSubscription(
      subscriptionId: 'sub-host-1-general',
      forumHostId: 'host-1',
      hostedBoardId: 'remote-general',
      localBoardId: 'local-general',
      readEnabled: true,
      writeEnabled: true,
      syncCursor: 9,
      retentionDays: 30,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final subscriptions = await repository.listSubscriptions(
    forumHostId: 'host-1',
  );
  expect(subscriptions.single.syncCursor, 9);

  await repository.updateSubscriptionCursor(
    'sub-host-1-general',
    15,
    now.add(const Duration(minutes: 1)),
  );
  expect(
    (await repository.listSubscriptions(
      forumHostId: 'host-1',
    )).single.syncCursor,
    15,
  );

  await repository.upsertPublicationTarget(
    BoardPublicationTarget(
      targetId: 'target-1',
      localSourceId: 'content-1',
      sourceType: BoardPublicationSourceType.contentItem,
      forumHostId: 'host-1',
      hostedBoardId: 'remote-general',
      mode: BoardPublicationMode.projection,
      status: BoardPublicationStatus.pending,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final targets = await repository.listPublicationTargets(
    status: BoardPublicationStatus.pending,
  );
  expect(targets.single.targetId, 'target-1');
}
