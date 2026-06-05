import 'package:ansible_node/services/app_sync_service.dart';
import 'package:ansible_node/services/content_publication_service.dart';
import 'package:ansible_node/services/nostr_relay_settings_store.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncAll publishes public content to the active relay', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    final now = DateTime.utc(2026, 5, 9, 14);
    final remoteNodes = DriftRemoteNodeRepository(db);
    final contentItems = DriftContentItemRepository(db);
    final publicationRepo = DriftPublicationRepository(db);

    await remoteNodes.create(
      RemoteNode(
        id: 'relay',
        name: 'Local relay',
        url: 'http://127.0.0.1:4001',
        createdAt: now,
        updatedAt: now,
        isActive: true,
      ),
    );
    await contentItems.create(
      ContentItem(
        id: 'note-1',
        authorDid: 'did:plc:alice',
        mode: ContentMode.note,
        title: 'Public note',
        body: 'Body',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        localOnly: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final service = AppSyncService(
      remoteNodeRepo: remoteNodes,
      boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
      boardRepo: DriftBoardRepository(db),
      threadRepo: DriftThreadRepository(db),
      postRepo: DriftPostRepository(db),
      contentItemRepo: contentItems,
      publicationRepo: publicationRepo,
      relaySettings: const EmptyNostrRelaySettingsStore(),
      keyStore: const InMemoryNostrKeyStore(),
      didSigner: _FakeDidSigner(),
      relayPublicationClient: _RecordingRelayPublicationClient(),
    );

    final result = await service.syncAll(pullRemote: false);

    expect(result.publishSummary.publicItems, 1);
    expect(result.publishSummary.enqueued, 1);
    expect(result.publishSummary.published, 1);
    expect(result.publishSummary.failed, 0);

    final targets = await publicationRepo.listTargets();
    expect(targets.single.protocol, PublicationProtocol.activityPub);
    expect(targets.single.status, PublicationStatus.published);
  });

  test('syncAll skips local-only public content', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    final now = DateTime.utc(2026, 5, 9, 14);
    final remoteNodes = DriftRemoteNodeRepository(db);
    final contentItems = DriftContentItemRepository(db);
    final publicationRepo = DriftPublicationRepository(db);

    await remoteNodes.create(
      RemoteNode(
        id: 'relay',
        name: 'Local relay',
        url: 'http://127.0.0.1:4001',
        createdAt: now,
        updatedAt: now,
        isActive: true,
      ),
    );
    await contentItems.create(
      ContentItem(
        id: 'note-local-public',
        authorDid: 'did:plc:alice',
        mode: ContentMode.note,
        title: 'Local public',
        body: 'Body',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        localOnly: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final service = AppSyncService(
      remoteNodeRepo: remoteNodes,
      boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
      boardRepo: DriftBoardRepository(db),
      threadRepo: DriftThreadRepository(db),
      postRepo: DriftPostRepository(db),
      contentItemRepo: contentItems,
      publicationRepo: publicationRepo,
      relaySettings: const EmptyNostrRelaySettingsStore(),
      keyStore: const InMemoryNostrKeyStore(),
      didSigner: _FakeDidSigner(),
      relayPublicationClient: _RecordingRelayPublicationClient(),
    );

    final result = await service.syncAll(pullRemote: false);

    expect(result.publishSummary.publicItems, 0);
    expect(result.publishSummary.enqueued, 0);
    expect(await publicationRepo.listTargets(), isEmpty);
  });

  test('syncAll enqueues relay ops for public murmur/note, idempotently', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    final now = DateTime.utc(2026, 6, 4, 14);
    final contentItems = DriftContentItemRepository(db);
    final opsQueue = InMemoryOpsQueueRepository();

    await contentItems.create(
      ContentItem(
        id: 'murmur-1',
        authorDid: 'did:plc:alice',
        mode: ContentMode.murmur,
        body: 'a public thought',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        localOnly: false,
        createdAt: now,
        updatedAt: now,
        publishedAt: now,
      ),
    );
    // Private content must never become an op.
    await contentItems.create(
      ContentItem(
        id: 'murmur-private',
        authorDid: 'did:plc:alice',
        mode: ContentMode.murmur,
        body: 'secret',
        status: ContentStatus.active,
        visibility: ContentVisibility.private,
        localOnly: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    AppSyncService build() => AppSyncService(
          remoteNodeRepo: DriftRemoteNodeRepository(db),
          boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
          boardRepo: DriftBoardRepository(db),
          threadRepo: DriftThreadRepository(db),
          postRepo: DriftPostRepository(db),
          contentItemRepo: contentItems,
          publicationRepo: DriftPublicationRepository(db),
          relaySettings: const EmptyNostrRelaySettingsStore(),
          keyStore: const InMemoryNostrKeyStore(),
          opsQueueRepo: opsQueue,
          opsDispatchService: OpsDispatchService(
            repository: opsQueue,
            signer: _FakeDidSigner(),
          ),
          didSigner: _FakeDidSigner(),
          relayPublicationClient: _RecordingRelayPublicationClient(),
        );

    await build().syncAll(pullRemote: false);
    var ops = await opsQueue.listAll();
    expect(ops.map((o) => o.entityId), contains('murmur-1'));
    expect(ops.any((o) => o.entityId == 'murmur-private'), isFalse);
    expect(ops.where((o) => o.entityType == 'murmur').length, 1);

    // Running again does not duplicate the op for the same entity.
    await build().syncAll(pullRemote: false);
    ops = await opsQueue.listAll();
    expect(ops.where((o) => o.entityId == 'murmur-1').length, 1);
  });
}

class EmptyNostrRelaySettingsStore implements NostrRelaySettingsStore {
  const EmptyNostrRelaySettingsStore();

  @override
  Future<List<NostrRelayPreference>> list() async => const [];

  @override
  Future<void> save(List<NostrRelayPreference> relays) async {}
}

class InMemoryNostrKeyStore implements NostrKeyStore {
  const InMemoryNostrKeyStore();

  @override
  Future<void> clear() async {}

  @override
  Future<NostrKeyMaterial?> read() async => null;

  @override
  Future<void> save(NostrKeyMaterial key) async {}
}

class _FakeDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return Ed25519Signature('a' * 128);
  }
}

class _RecordingRelayPublicationClient implements RelayPublicationClient {
  @override
  Future<RelayPublicationResult> publish({
    required String baseUrl,
    required RelayPublicationIntent intent,
  }) async {
    return RelayPublicationResult(publicationId: 'remote-${intent.intentId}');
  }
}
