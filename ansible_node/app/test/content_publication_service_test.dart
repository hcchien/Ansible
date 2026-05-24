import 'package:ansible_node/services/content_publication_service.dart';
import 'package:ansible_node/services/nostr_publication_service.dart';
import 'package:ansible_node/services/nostr_relay_settings_store.dart';
import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public content enqueues signed Nostr targets and publishes them',
    () async {
      final now = DateTime.utc(2026, 5, 9);
      final contentItems = InMemoryContentItemRepository();
      final publications = InMemoryPublicationRepository();
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(
          privateKeyHex:
              '0000000000000000000000000000000000000000000000000000000000000003',
          publicKeyHex: SchnorrSigningBridge.derivePublicKeyHex(
            '0000000000000000000000000000000000000000000000000000000000000003',
          ),
        ),
      );
      final item = ContentItem(
        id: 'murmur-1',
        authorDid: 'did:plc:alice',
        mode: ContentMode.murmur,
        body: 'hello public',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        createdAt: now,
        updatedAt: now,
        localOnly: false,
      );
      await contentItems.create(item);
      final relayClient = _RecordingRelayClient();

      final result =
          await ContentPublicationService(
            contentItems: contentItems,
            publications: publications,
            relaySettings: _FakeRelaySettingsStore([
              const NostrRelayPreference(
                url: 'wss://relay.example',
                write: true,
              ),
            ]),
            keyStore: keyStore,
            signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
            relayClient: relayClient,
          ).publishContentItem(
            item,
            distributionPreference: DistributionPreference.nostr,
          );

      expect(result.enqueued, 1);
      expect(result.published, 1);
      expect(relayClient.calls.single.endpoint, 'wss://relay.example');
      final targets = await publications.listTargetsForIntent(
        (await publications.listTargets()).single.intentId,
      );
      expect(targets.single.status, PublicationStatus.published);
    },
  );

  test('private content does not enqueue publication targets', () async {
    final now = DateTime.utc(2026, 5, 9);
    final publications = InMemoryPublicationRepository();
    final item = ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Private',
      body: 'local only',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: now,
      updatedAt: now,
      localOnly: true,
    );

    final result =
        await ContentPublicationService(
          contentItems: InMemoryContentItemRepository(),
          publications: publications,
          relaySettings: _FakeRelaySettingsStore([
            const NostrRelayPreference(url: 'wss://relay.example', write: true),
          ]),
          keyStore: InMemoryNostrKeyStore(),
          signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
          relayClient: _RecordingRelayClient(),
        ).publishContentItem(
          item,
          distributionPreference: DistributionPreference.nostr,
        );

    expect(result.skippedReason, 'private_or_local_only');
    expect(await publications.listTargets(), isEmpty);
  });

  test(
    'local-only public content does not enqueue publication targets',
    () async {
      final now = DateTime.utc(2026, 5, 9);
      final publications = InMemoryPublicationRepository();
      final item = ContentItem(
        id: 'note-local-public',
        authorDid: 'did:plc:alice',
        mode: ContentMode.note,
        title: 'Local public',
        body: 'visible locally but not federated',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        createdAt: now,
        updatedAt: now,
        localOnly: true,
      );

      final result =
          await ContentPublicationService(
            contentItems: InMemoryContentItemRepository(),
            publications: publications,
            relaySettings: _FakeRelaySettingsStore([
              const NostrRelayPreference(
                url: 'wss://relay.example',
                write: true,
              ),
            ]),
            keyStore: InMemoryNostrKeyStore(),
            signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
            relayClient: _RecordingRelayClient(),
          ).publishContentItem(
            item,
            distributionPreference: DistributionPreference.nostr,
          );

      expect(result.skippedReason, 'private_or_local_only');
      expect(await publications.listTargets(), isEmpty);
    },
  );

  test(
    'nostr and activitypub preference publishes to Nostr and active relay node',
    () async {
      final now = DateTime.utc(2026, 5, 9);
      final contentItems = InMemoryContentItemRepository();
      final publications = InMemoryPublicationRepository();
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(
          privateKeyHex:
              '0000000000000000000000000000000000000000000000000000000000000003',
          publicKeyHex: SchnorrSigningBridge.derivePublicKeyHex(
            '0000000000000000000000000000000000000000000000000000000000000003',
          ),
        ),
      );
      final item = ContentItem(
        id: 'note-1',
        authorDid: 'did:key:z6MkAlice',
        mode: ContentMode.note,
        title: 'Relay note',
        body: 'published through both adapters',
        status: ContentStatus.active,
        visibility: ContentVisibility.public,
        createdAt: now,
        updatedAt: now,
        localOnly: false,
      );
      await contentItems.create(item);
      final nostrRelayClient = _RecordingRelayClient();
      final relayPublicationClient = _RecordingRelayPublicationClient();

      final result =
          await ContentPublicationService(
            contentItems: contentItems,
            publications: publications,
            relaySettings: _FakeRelaySettingsStore([
              const NostrRelayPreference(
                url: 'wss://relay.example',
                write: true,
              ),
            ]),
            remoteNodes: _FakeRemoteNodeRepository(
              active: RemoteNode(
                id: 'node-1',
                name: 'Ansible relay',
                url: 'https://relay.trisaura.io',
                createdAt: now,
                updatedAt: now,
              ),
            ),
            keyStore: keyStore,
            didSigner: _FakeDidSigner(),
            signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
            relayClient: nostrRelayClient,
            relayPublicationClient: relayPublicationClient,
          ).publishContentItem(
            item,
            distributionPreference: DistributionPreference.nostrAndActivityPub,
          );

      expect(result.enqueued, 2);
      expect(result.published, 2);
      expect(nostrRelayClient.calls.single.endpoint, 'wss://relay.example');
      expect(
        relayPublicationClient.calls.single.baseUrl,
        'https://relay.trisaura.io',
      );
      expect(
        relayPublicationClient.calls.single.intent.signatureScheme,
        'ed25519',
      );
      expect(
        relayPublicationClient.calls.single.intent.payload['title'],
        'Relay note',
      );
    },
  );

  test('activitypub relay failure is surfaced in publication result', () async {
    final now = DateTime.utc(2026, 5, 9);
    final contentItems = InMemoryContentItemRepository();
    final publications = InMemoryPublicationRepository();
    final item = ContentItem(
      id: 'note-1',
      authorDid: 'did:key:z6MkAlice',
      mode: ContentMode.note,
      title: 'Relay note',
      body: 'published through relay adapter',
      status: ContentStatus.active,
      visibility: ContentVisibility.public,
      createdAt: now,
      updatedAt: now,
      localOnly: false,
    );
    await contentItems.create(item);

    final result =
        await ContentPublicationService(
          contentItems: contentItems,
          publications: publications,
          relaySettings: _FakeRelaySettingsStore(const []),
          remoteNodes: _FakeRemoteNodeRepository(
            active: RemoteNode(
              id: 'node-1',
              name: 'Ansible relay',
              url: 'https://relay.trisaura.io',
              createdAt: now,
              updatedAt: now,
            ),
          ),
          keyStore: InMemoryNostrKeyStore(),
          didSigner: _FakeDidSigner(),
          signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
          relayPublicationClient: _FailingRelayPublicationClient(),
        ).publishContentItem(
          item,
          distributionPreference: DistributionPreference.activityPub,
        );

    expect(result.enqueued, 1);
    expect(result.published, 0);
    expect(result.failed, 1);
    expect(result.errors.single, contains('unverified_did'));
    final target = (await publications.listTargets()).single;
    expect(target.status, PublicationStatus.failed);
    expect(target.error, contains('unverified_did'));
  });

  test('activitypub failed target is retried on the next publish', () async {
    final now = DateTime.utc(2026, 5, 9);
    final contentItems = InMemoryContentItemRepository();
    final publications = InMemoryPublicationRepository();
    final item = ContentItem(
      id: 'note-1',
      authorDid: 'did:key:z6MkAlice',
      mode: ContentMode.note,
      title: 'Relay note',
      body: 'retry through relay adapter',
      status: ContentStatus.active,
      visibility: ContentVisibility.public,
      createdAt: now,
      updatedAt: now,
      localOnly: false,
    );
    await contentItems.create(item);
    final remoteNodes = _FakeRemoteNodeRepository(
      active: RemoteNode(
        id: 'node-1',
        name: 'Ansible relay',
        url: 'https://relay.trisaura.io',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await ContentPublicationService(
      contentItems: contentItems,
      publications: publications,
      relaySettings: _FakeRelaySettingsStore(const []),
      remoteNodes: remoteNodes,
      keyStore: InMemoryNostrKeyStore(),
      didSigner: _FakeDidSigner(),
      signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
      relayPublicationClient: _FailingRelayPublicationClient(),
    ).publishContentItem(
      item,
      distributionPreference: DistributionPreference.activityPub,
    );

    final retryClient = _RecordingRelayPublicationClient();
    final result =
        await ContentPublicationService(
          contentItems: contentItems,
          publications: publications,
          relaySettings: _FakeRelaySettingsStore(const []),
          remoteNodes: remoteNodes,
          keyStore: InMemoryNostrKeyStore(),
          didSigner: _FakeDidSigner(),
          signingBridge: const SchnorrSigningBridge(auxRandHex: _zeroAuxRand),
          relayPublicationClient: retryClient,
        ).publishContentItem(
          item,
          distributionPreference: DistributionPreference.activityPub,
        );

    expect(result.enqueued, 1);
    expect(result.published, 1);
    expect(result.failed, 0);
    expect(retryClient.calls.single.baseUrl, 'https://relay.trisaura.io');
    final target = (await publications.listTargets()).single;
    expect(target.status, PublicationStatus.published);
    expect(target.error, isNull);
  });
}

const _zeroAuxRand =
    '0000000000000000000000000000000000000000000000000000000000000000';

class _FakeRelaySettingsStore implements NostrRelaySettingsStore {
  _FakeRelaySettingsStore(this.relays);

  final List<NostrRelayPreference> relays;

  @override
  Future<List<NostrRelayPreference>> list() async => relays;

  @override
  Future<void> save(List<NostrRelayPreference> relays) async {}
}

class _RecordingRelayClient implements NostrRelayClient {
  final calls = <({String endpoint, NostrEvent event})>[];

  @override
  Future<void> publish({
    required String endpoint,
    required NostrEvent event,
  }) async {
    calls.add((endpoint: endpoint, event: event));
  }
}

class _RecordingRelayPublicationClient implements RelayPublicationClient {
  final calls = <({String baseUrl, RelayPublicationIntent intent})>[];

  @override
  Future<RelayPublicationResult> publish({
    required String baseUrl,
    required RelayPublicationIntent intent,
  }) async {
    calls.add((baseUrl: baseUrl, intent: intent));
    return const RelayPublicationResult(publicationId: 'pub_1');
  }
}

class _FailingRelayPublicationClient implements RelayPublicationClient {
  @override
  Future<RelayPublicationResult> publish({
    required String baseUrl,
    required RelayPublicationIntent intent,
  }) async {
    throw StateError('Relay publication failed: 401 unverified_did');
  }
}

class _FakeDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return Ed25519Signature('1' * 128);
  }
}

class _FakeRemoteNodeRepository implements RemoteNodeRepository {
  _FakeRemoteNodeRepository({this.active});

  final RemoteNode? active;

  @override
  Future<void> create(RemoteNode node) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<RemoteNode?> getActive() async => active;

  @override
  Future<RemoteNode?> getById(String id) async => null;

  @override
  Future<List<RemoteNode>> list() async => [if (active != null) active!];

  @override
  Future<void> update(RemoteNode node) async {}

  @override
  Future<void> updateSyncCursor(
    String id,
    int cursor,
    DateTime syncTime,
  ) async {}
}
