import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:test/test.dart';

void main() {
  group('ProductionNostrEventSigner', () {
    test('signs event ids through the native bridge', () async {
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(privateKeyHex: 'a' * 64, publicKeyHex: 'b' * 64),
      );
      final bridge = _RecordingSigningBridge(signatureHex: 'c' * 128);
      final signer = ProductionNostrEventSigner(
        keyStore: keyStore,
        signingBridge: bridge,
      );
      const draft = NostrEventDraft(
        pubkey:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        createdAt: 0,
        kind: 1,
        tags: [],
        content: '',
      );

      final event = await signer.sign(draft);

      expect(event.id, draft.computeId());
      expect(event.sig, 'c' * 128);
      expect(bridge.privateKeyHex, 'a' * 64);
      expect(bridge.eventIdHex, draft.computeId());
    });

    test('fails closed without local key material', () async {
      final signer = ProductionNostrEventSigner(
        keyStore: InMemoryNostrKeyStore(),
        signingBridge: _RecordingSigningBridge(signatureHex: 'c' * 128),
      );

      await expectLater(
        signer.sign(_draft(pubkey: 'b' * 64)),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects bridge dev signatures', () async {
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(privateKeyHex: 'a' * 64, publicKeyHex: 'b' * 64),
      );
      final signer = ProductionNostrEventSigner(
        keyStore: keyStore,
        signingBridge: _RecordingSigningBridge(signatureHex: 'dev-signature'),
      );

      await expectLater(
        signer.sign(_draft(pubkey: 'b' * 64)),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects signing with a mismatched public key', () async {
      final keyStore = InMemoryNostrKeyStore();
      await keyStore.save(
        NostrKeyMaterial(privateKeyHex: 'a' * 64, publicKeyHex: 'b' * 64),
      );
      final signer = ProductionNostrEventSigner(
        keyStore: keyStore,
        signingBridge: _RecordingSigningBridge(signatureHex: 'c' * 128),
      );

      await expectLater(
        signer.sign(_draft(pubkey: 'd' * 64)),
        throwsA(isA<StateError>()),
      );
    });
  });
}

NostrEventDraft _draft({required String pubkey}) {
  return NostrEventDraft(
    pubkey: pubkey,
    createdAt: 0,
    kind: 1,
    tags: const [],
    content: '',
  );
}

class _RecordingSigningBridge implements NostrSigningBridge {
  final String signatureHex;
  String? privateKeyHex;
  String? eventIdHex;

  _RecordingSigningBridge({required this.signatureHex});

  @override
  Future<String> signEventId({
    required String privateKeyHex,
    required String eventIdHex,
  }) async {
    this.privateKeyHex = privateKeyHex;
    this.eventIdHex = eventIdHex;
    return signatureHex;
  }
}
