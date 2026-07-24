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
  test('pull-only sync does not publish local content', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final now = DateTime.utc(2026, 7, 21);
    final contentItems = DriftContentItemRepository(db);
    final publications = DriftPublicationRepository(db);
    await contentItems.create(
      ContentItem(
        id: 'pending-note',
        authorDid: 'did:elix:alice',
        mode: ContentMode.note,
        body: 'remains local during background refresh',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        localOnly: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final result = await AppSyncService(
      remoteNodeRepo: DriftRemoteNodeRepository(db),
      boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
      boardRepo: DriftBoardRepository(db),
      threadRepo: DriftThreadRepository(db),
      postRepo: DriftPostRepository(db),
      contentItemRepo: contentItems,
      publicationRepo: publications,
      relaySettings: const EmptyNostrRelaySettingsStore(),
      keyStore: const InMemoryNostrKeyStore(),
    ).syncAll(pullRemote: false, pushLocal: false);

    expect(result.publishSummary.publicItems, 0);
    expect(await publications.listTargets(), isEmpty);
    expect(
      (await contentItems.getById('pending-note'))?.signatureVerified,
      isFalse,
    );
  });

  test('reduced-trust read-only sync never publishes local content', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final now = DateTime.utc(2026, 7, 24);
    final contentItems = DriftContentItemRepository(db);
    final publications = DriftPublicationRepository(db);
    await contentItems.create(
      ContentItem(
        id: 'pending-linux-note',
        authorDid: 'did:elix:alice',
        mode: ContentMode.note,
        body: 'must remain local without WebAuthn',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        localOnly: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final result = await AppSyncService(
      remoteNodeRepo: DriftRemoteNodeRepository(db),
      boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
      boardRepo: DriftBoardRepository(db),
      threadRepo: DriftThreadRepository(db),
      postRepo: DriftPostRepository(db),
      contentItemRepo: contentItems,
      publicationRepo: publications,
      relaySettings: const EmptyNostrRelaySettingsStore(),
      keyStore: const InMemoryNostrKeyStore(),
      allowIdentityWrites: false,
    ).syncAll(pullRemote: false);

    expect(result.publishSummary.publicItems, 0);
    expect(result.publishSummary.skippedReasons, {'webauthnUnavailable'});
    expect(await publications.listTargets(), isEmpty);
  });

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

  test(
    'syncAll does not re-sign content owned by a previous local DID',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final now = DateTime.utc(2026, 7, 17);
      final contentItems = DriftContentItemRepository(db);
      final publicationRepo = DriftPublicationRepository(db);
      final opsQueue = InMemoryOpsQueueRepository();
      await contentItems.create(
        ContentItem(
          id: 'legacy-note',
          authorDid: 'did:plc:previous',
          mode: ContentMode.note,
          title: 'Legacy note',
          body: 'Keep locally without impersonating its author.',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          localOnly: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await AppSyncService(
        remoteNodeRepo: DriftRemoteNodeRepository(db),
        boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
        boardRepo: DriftBoardRepository(db),
        threadRepo: DriftThreadRepository(db),
        postRepo: DriftPostRepository(db),
        contentItemRepo: contentItems,
        publicationRepo: publicationRepo,
        relaySettings: const EmptyNostrRelaySettingsStore(),
        keyStore: const InMemoryNostrKeyStore(),
        followerDid: 'did:elix:current',
        opsQueueRepo: opsQueue,
        opsDispatchService: OpsDispatchService(
          repository: opsQueue,
          signer: _FakeDidSigner(),
        ),
        didSigner: _FakeDidSigner(),
        relayPublicationClient: _RecordingRelayPublicationClient(),
      ).syncAll(pullRemote: false);

      expect(result.publishSummary.publicItems, 0);
      expect(await opsQueue.listAll(), isEmpty);
      expect(await publicationRepo.listTargets(), isEmpty);
    },
  );

  test(
    'syncAll enqueues relay ops for public murmur/note, idempotently',
    () async {
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
    },
  );

  test(
    'syncAll publishes federated follow ops and converges on unfollow',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final now = DateTime.utc(2026, 6, 4, 14);
      final opsQueue = InMemoryOpsQueueRepository();
      final follows = InMemoryFollowRepository();

      await follows.upsertTarget(
        FollowTarget(
          targetId: 'target-bob',
          targetType: FollowTargetType.user,
          canonicalUri: 'did:plc:bob',
          displayName: 'bob',
          did: 'did:plc:bob',
          createdAt: now,
          updatedAt: now,
        ),
      );
      // A localOnly follow must never be published.
      await follows.upsertTarget(
        FollowTarget(
          targetId: 'target-eve',
          targetType: FollowTargetType.user,
          canonicalUri: 'did:plc:eve',
          displayName: 'eve',
          did: 'did:plc:eve',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await follows.upsertEdge(
        FollowEdge(
          followId: 'f-bob',
          followerDid: 'did:plc:reader',
          targetId: 'target-bob',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.federated,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );
      await follows.upsertEdge(
        FollowEdge(
          followId: 'f-eve',
          followerDid: 'did:plc:reader',
          targetId: 'target-eve',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );

      AppSyncService build() => AppSyncService(
        remoteNodeRepo: DriftRemoteNodeRepository(db),
        boardSyncConfigRepo: DriftBoardSyncConfigRepository(db),
        boardRepo: DriftBoardRepository(db),
        threadRepo: DriftThreadRepository(db),
        postRepo: DriftPostRepository(db),
        contentItemRepo: DriftContentItemRepository(db),
        publicationRepo: DriftPublicationRepository(db),
        relaySettings: const EmptyNostrRelaySettingsStore(),
        keyStore: const InMemoryNostrKeyStore(),
        followRepository: follows,
        followerDid: 'did:plc:reader',
        opsQueueRepo: opsQueue,
        opsDispatchService: OpsDispatchService(
          repository: opsQueue,
          signer: _FakeDidSigner(),
        ),
        didSigner: _FakeDidSigner(),
        relayPublicationClient: _RecordingRelayPublicationClient(),
      );

      await build().syncAll(pullRemote: false);
      var followOps = (await opsQueue.listAll())
          .where((o) => o.entityType == 'follow')
          .toList();
      expect(followOps.length, 1);
      expect(followOps.single.opType, 'insert');
      expect(followOps.single.entityId, 'did:plc:bob');
      // localOnly follow never produced an op.
      expect(followOps.any((o) => o.entityId == 'did:plc:eve'), isFalse);

      // Idempotent: re-running does not re-publish the active follow.
      await build().syncAll(pullRemote: false);
      expect(
        (await opsQueue.listAll())
            .where((o) => o.entityType == 'follow' && o.opType == 'insert')
            .length,
        1,
      );

      // Unfollow: cancel the edge -> a delete op converges the graph.
      await follows.updateEdgeStatus('f-bob', FollowStatus.cancelled, now);
      await build().syncAll(pullRemote: false);
      followOps = (await opsQueue.listAll())
          .where((o) => o.entityType == 'follow')
          .toList();
      expect(
        followOps.any(
          (o) => o.opType == 'delete' && o.entityId == 'did:plc:bob',
        ),
        isTrue,
      );
    },
  );

  test(
    'syncAll publishes the self profile op and re-publishes only on change',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final now = DateTime.utc(2026, 6, 4, 14);
      final opsQueue = InMemoryOpsQueueRepository();
      final contacts = DriftContactRepository(db);

      await contacts.upsertContact(
        ContactRecord(
          subjectDid: 'did:plc:reader',
          handle: 'me.example',
          displayName: 'Me',
          source: 'self',
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
        contentItemRepo: DriftContentItemRepository(db),
        publicationRepo: DriftPublicationRepository(db),
        relaySettings: const EmptyNostrRelaySettingsStore(),
        keyStore: const InMemoryNostrKeyStore(),
        contactRepository: contacts,
        followerDid: 'did:plc:reader',
        opsQueueRepo: opsQueue,
        opsDispatchService: OpsDispatchService(
          repository: opsQueue,
          signer: _FakeDidSigner(),
        ),
        didSigner: _FakeDidSigner(),
        relayPublicationClient: _RecordingRelayPublicationClient(),
      );

      await build().syncAll(pullRemote: false);
      var profileOps = (await opsQueue.listAll())
          .where((o) => o.entityType == 'profile')
          .toList();
      expect(profileOps.length, 1);
      expect(profileOps.single.entityId, 'did:plc:reader');
      expect(
        CrdtOpBuilder.decodePayload(profileOps.single.payload)['handle'],
        'me.example',
      );

      // Unchanged profile -> no new op.
      await build().syncAll(pullRemote: false);
      expect(
        (await opsQueue.listAll())
            .where((o) => o.entityType == 'profile')
            .length,
        1,
      );

      // Changed display name -> a new profile op is published.
      await contacts.upsertContact(
        ContactRecord(
          subjectDid: 'did:plc:reader',
          handle: 'me.example',
          displayName: 'Me Renamed',
          source: 'self',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await build().syncAll(pullRemote: false);
      expect(
        (await opsQueue.listAll())
            .where((o) => o.entityType == 'profile')
            .length,
        2,
      );
    },
  );
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
