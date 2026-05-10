import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('RemoteNode exposes ForumHost metadata during migration', () {
    final now = DateTime.utc(2026, 5, 10);
    final node = RemoteNode(
      id: 'remote-1',
      name: 'Local Forum',
      url: 'https://forum.example',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final host = node.toForumHost();

    expect(host.forumHostId, 'remote-1');
    expect(host.displayName, 'Local Forum');
    expect(host.serverKind, 'ansibleForumHost');
    expect(host.baseUrl, 'https://forum.example');
    expect(host.isActive, isTrue);
  });

  test('DriftRemoteNodeRepository lists ForumHosts from RemoteNodes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final now = DateTime.utc(2026, 5, 10);
    final repo = DriftRemoteNodeRepository(db);
    await repo.create(
      RemoteNode(
        id: 'remote-1',
        name: 'Active Forum',
        url: 'https://forum.example',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repo.create(
      RemoteNode(
        id: 'remote-2',
        name: 'Inactive Forum',
        url: 'https://inactive.example',
        isActive: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final activeHosts = await repo.listForumHosts(includeInactive: false);

    expect(activeHosts.map((host) => host.forumHostId), ['remote-1']);
  });

  test('BoardSyncConfig converts to subscription only with projection', () {
    final now = DateTime.utc(2026, 5, 10);
    final config = BoardSyncConfig(
      id: 'remote-1_local-general',
      remoteNodeId: 'remote-1',
      boardId: 'local-general',
      syncEnabled: true,
      retentionDays: 45,
      createdAt: now,
      updatedAt: now,
    );
    final projection = HostedBoardProjection(
      localBoardId: 'local-general',
      forumHostId: 'remote-1',
      hostedBoardId: 'hosted-general',
      canonicalBoardUri: 'https://forum.example/boards/hosted-general',
      remoteSlug: 'general',
      localSlug: 'general',
      title: 'General',
      createdAt: now,
      updatedAt: now,
    );

    expect(config.toBoardSubscription(null), isNull);

    final subscription = config.toBoardSubscription(projection);

    expect(subscription, isNotNull);
    expect(subscription!.subscriptionId, 'remote-1_hosted-general');
    expect(subscription.forumHostId, 'remote-1');
    expect(subscription.hostedBoardId, 'hosted-general');
    expect(subscription.localBoardId, 'local-general');
    expect(subscription.readEnabled, isTrue);
    expect(subscription.writeEnabled, isTrue);
    expect(subscription.retentionDays, 45);
  });
}
