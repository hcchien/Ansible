import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/relay_reputation_presentation_service.dart';
import 'package:ansible_node/services/vc_presentation_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presents the Wallet VP and caches the Relay-derived tier', () async {
    final reputation = InMemoryDidReputationRepository();
    final relayClient = _RecordingAtProtoClient();
    final now = DateTime.utc(2026, 7, 21, 3);
    final node = RemoteNode(
      id: 'relay-dev',
      name: 'Relay dev',
      url: 'https://relay.example',
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );

    final result = await RelayReputationPresentationService(
      walletRepository: InMemoryWalletRepository(),
      reputationRepository: reputation,
      presentationBuilder:
          ({
            required holderDid,
            required audience,
            required nonce,
            required now,
          }) async => VcPresentationEnvelope(
            credentialId: 'humanity-1',
            verifiablePresentation: {
              'holder': holderDid,
              'audience': audience,
              'nonce': nonce,
            },
          ),
      clientFactory: (_) => relayClient,
    ).present(holderDid: 'did:elix:alice', node: node, now: now);

    expect(result.presented, isTrue);
    expect(result.tier, 'verified_human');
    expect(relayClient.holderDid, 'did:elix:alice');
    expect(relayClient.vp?['audience'], node.url);
    expect(await reputation.tierFor('did:elix:alice'), 'verified_human');
  });

  test('absence of a Humanity VC leaves the account at basic tier', () async {
    final reputation = InMemoryDidReputationRepository();
    final node = RemoteNode(
      id: 'relay-dev',
      name: 'Relay dev',
      url: 'https://relay.example',
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
      isActive: true,
    );

    final result = await RelayReputationPresentationService(
      walletRepository: InMemoryWalletRepository(),
      reputationRepository: reputation,
      presentationBuilder:
          ({
            required holderDid,
            required audience,
            required nonce,
            required now,
          }) async => null,
      clientFactory: (_) => throw StateError('Relay must not be called'),
    ).present(holderDid: 'did:elix:alice', node: node);

    expect(result.presented, isFalse);
    expect(await reputation.tierFor('did:elix:alice'), 'basic');
  });
}

class _RecordingAtProtoClient extends AtProtoClient {
  _RecordingAtProtoClient() : super(baseUrl: 'https://relay.example');

  String? holderDid;
  Map<String, dynamic>? vp;

  @override
  Future<String> presentVp({
    required String holderDid,
    required Map<String, dynamic> vp,
    Map<String, dynamic>? nostrBinding,
  }) async {
    this.holderDid = holderDid;
    this.vp = vp;
    return 'verified_human';
  }
}
