import 'package:ansible_node/services/nostr_publication_service.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NostrPublicationService', () {
    test(
      'projects, signs, publishes, and marks relay target published',
      () async {
        final now = DateTime.utc(2026, 5, 9);
        final contentItems = InMemoryContentItemRepository();
        final publications = InMemoryPublicationRepository();
        final relayClient = _RecordingNostrRelayClient();
        final privateKeyHex =
            '0000000000000000000000000000000000000000000000000000000000000003';
        final publicKeyHex = SchnorrSigningBridge.derivePublicKeyHex(
          privateKeyHex,
        );
        final keyStore = InMemoryNostrKeyStore();
        await keyStore.save(
          NostrKeyMaterial(
            privateKeyHex: privateKeyHex,
            publicKeyHex: publicKeyHex,
          ),
        );
        await contentItems.create(
          ContentItem(
            id: 'murmur-1',
            authorDid: 'did:plc:alice',
            mode: ContentMode.murmur,
            body: 'hello relay',
            status: ContentStatus.active,
            visibility: ContentVisibility.public,
            createdAt: now,
            updatedAt: now,
            localOnly: false,
          ),
        );
        await publications.enqueueIntent(
          _intent(
            id: 'intent-1',
            contentItemId: 'murmur-1',
            signature: 'c' * 128,
            createdAt: now,
          ),
          targets: [
            _target(
              id: 'target-1',
              intentId: 'intent-1',
              endpoint: 'wss://relay.example',
            ),
          ],
        );
        final service = NostrPublicationService(
          contentItems: contentItems,
          publications: publications,
          keyStore: keyStore,
          signer: ProductionNostrEventSigner(
            keyStore: keyStore,
            signingBridge: SchnorrSigningBridge(auxRandHex: '00' * 32),
          ),
          relayClient: relayClient,
        );

        final result = await service.publishPending(limit: 10);

        expect(result.published, 1);
        expect(result.failed, 0);
        expect(relayClient.calls.single.endpoint, 'wss://relay.example');
        expect(relayClient.calls.single.event.kind, 1);
        expect(relayClient.calls.single.event.content, 'hello relay');
        expect(relayClient.calls.single.event.pubkey, publicKeyHex);
        expect(relayClient.calls.single.event.sig, hasLength(128));

        final targets = await publications.listTargetsForIntent('intent-1');
        expect(targets.single.status, PublicationStatus.published);
        expect(targets.single.remoteId, relayClient.calls.single.event.id);
        expect(
          (await publications.getIntentById('intent-1'))!.status,
          PublicationStatus.complete,
        );
      },
    );

    test('keeps per-relay failures isolated from successful relays', () async {
      final now = DateTime.utc(2026, 5, 9);
      final contentItems = InMemoryContentItemRepository();
      final publications = InMemoryPublicationRepository();
      final relayClient = _RecordingNostrRelayClient(
        failingEndpoints: {'wss://down.example'},
      );
      final privateKeyHex =
          '0000000000000000000000000000000000000000000000000000000000000003';
      final publicKeyHex = SchnorrSigningBridge.derivePublicKeyHex(
        privateKeyHex,
      );
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(
          privateKeyHex: privateKeyHex,
          publicKeyHex: publicKeyHex,
        ),
      );
      await contentItems.create(
        ContentItem(
          id: 'note-1',
          authorDid: 'did:plc:alice',
          mode: ContentMode.note,
          title: 'Note',
          body: 'long body',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          createdAt: now,
          updatedAt: now,
          localOnly: false,
        ),
      );
      await publications.enqueueIntent(
        _intent(
          id: 'intent-2',
          contentItemId: 'note-1',
          signature: 'd' * 128,
          createdAt: now,
        ),
        targets: [
          _target(
            id: 'target-down',
            intentId: 'intent-2',
            endpoint: 'wss://down.example',
          ),
          _target(
            id: 'target-up',
            intentId: 'intent-2',
            endpoint: 'wss://up.example',
          ),
        ],
      );
      final service = NostrPublicationService(
        contentItems: contentItems,
        publications: publications,
        keyStore: keyStore,
        signer: ProductionNostrEventSigner(
          keyStore: keyStore,
          signingBridge: SchnorrSigningBridge(auxRandHex: '00' * 32),
        ),
        relayClient: relayClient,
      );

      final result = await service.publishPending(limit: 10);

      expect(result.published, 1);
      expect(result.failed, 1);
      final targets = {
        for (final target in await publications.listTargetsForIntent(
          'intent-2',
        ))
          target.targetId: target,
      };
      expect(targets['target-up']!.status, PublicationStatus.published);
      expect(targets['target-down']!.status, PublicationStatus.failed);
      expect(targets['target-down']!.error, contains('relay down'));
    });

    test('does not publish targets whose intent lacks real signature', () async {
      final now = DateTime.utc(2026, 5, 9);
      final contentItems = InMemoryContentItemRepository();
      final publications = InMemoryPublicationRepository();
      final relayClient = _RecordingNostrRelayClient();
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
      await contentItems.create(
        ContentItem(
          id: 'unsigned-murmur',
          authorDid: 'did:plc:alice',
          mode: ContentMode.murmur,
          body: 'stay local',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          createdAt: now,
          updatedAt: now,
          localOnly: false,
        ),
      );
      await publications.enqueueIntent(
        PublicationIntent(
          intentId: 'intent-unsigned',
          authorDid: 'did:plc:alice',
          contentItemId: 'unsigned-murmur',
          action: PublicationAction.publish,
          visibility: ContentVisibility.public,
          distributionPreference: DistributionPreference.nostr,
          status: PublicationStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
        targets: [
          _target(
            id: 'target-unsigned',
            intentId: 'intent-unsigned',
            endpoint: 'wss://relay.example',
          ),
        ],
      );
      final service = NostrPublicationService(
        contentItems: contentItems,
        publications: publications,
        keyStore: keyStore,
        signer: ProductionNostrEventSigner(
          keyStore: keyStore,
          signingBridge: SchnorrSigningBridge(auxRandHex: '00' * 32),
        ),
        relayClient: relayClient,
      );

      final result = await service.publishPending(limit: 10);

      expect(result.published, 0);
      expect(result.failed, 0);
      expect(relayClient.calls, isEmpty);
    });

    test('resets a failed target and retries it', () async {
      final now = DateTime.utc(2026, 5, 9);
      final contentItems = InMemoryContentItemRepository();
      final publications = InMemoryPublicationRepository();
      final relayClient = _RecordingNostrRelayClient();
      final privateKeyHex =
          '0000000000000000000000000000000000000000000000000000000000000003';
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(
          privateKeyHex: privateKeyHex,
          publicKeyHex: SchnorrSigningBridge.derivePublicKeyHex(privateKeyHex),
        ),
      );
      await contentItems.create(
        ContentItem(
          id: 'retry-murmur',
          authorDid: 'did:plc:alice',
          mode: ContentMode.murmur,
          body: 'retry me',
          status: ContentStatus.active,
          visibility: ContentVisibility.public,
          createdAt: now,
          updatedAt: now,
          localOnly: false,
        ),
      );
      await publications.enqueueIntent(
        _intent(
          id: 'intent-retry',
          contentItemId: 'retry-murmur',
          signature: 'e' * 128,
          createdAt: now,
        ),
        targets: [
          _target(
            id: 'target-retry',
            intentId: 'intent-retry',
            endpoint: 'wss://relay.example',
          ),
        ],
      );
      await publications.markTargetFailed('target-retry', 'relay down');
      final service = NostrPublicationService(
        contentItems: contentItems,
        publications: publications,
        keyStore: keyStore,
        signer: ProductionNostrEventSigner(
          keyStore: keyStore,
          signingBridge: SchnorrSigningBridge(auxRandHex: '00' * 32),
        ),
        relayClient: relayClient,
      );

      final result = await service.retryTarget('target-retry');

      expect(result.published, 1);
      expect(result.failed, 0);
      expect(relayClient.calls.single.event.content, 'retry me');
      final target = (await publications.getTargetById('target-retry'))!;
      expect(target.status, PublicationStatus.published);
      expect(target.error, isNull);
    });
  });
}

PublicationIntent _intent({
  required String id,
  required String contentItemId,
  required String signature,
  required DateTime createdAt,
}) {
  return PublicationIntent(
    intentId: id,
    authorDid: 'did:plc:alice',
    contentItemId: contentItemId,
    action: PublicationAction.publish,
    visibility: ContentVisibility.public,
    distributionPreference: DistributionPreference.nostr,
    status: PublicationStatus.pending,
    signature: signature,
    signatureScheme: 'schnorr-secp256k1',
    signedAt: createdAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

PublicationTarget _target({
  required String id,
  required String intentId,
  required String endpoint,
}) {
  return PublicationTarget(
    targetId: id,
    intentId: intentId,
    protocol: PublicationProtocol.nostr,
    endpoint: endpoint,
    status: PublicationStatus.pending,
  );
}

class _RecordingNostrRelayClient implements NostrRelayClient {
  final Set<String> failingEndpoints;
  final List<_PublishCall> calls = [];

  _RecordingNostrRelayClient({this.failingEndpoints = const {}});

  @override
  Future<void> publish({
    required String endpoint,
    required NostrEvent event,
  }) async {
    if (failingEndpoints.contains(endpoint)) {
      throw NostrRelayPublishException('relay down: $endpoint');
    }
    calls.add(_PublishCall(endpoint: endpoint, event: event));
  }
}

class _PublishCall {
  final String endpoint;
  final NostrEvent event;

  const _PublishCall({required this.endpoint, required this.event});
}
