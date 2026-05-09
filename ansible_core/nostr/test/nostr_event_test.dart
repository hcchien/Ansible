import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:test/test.dart';

void main() {
  group('NIP-01 events', () {
    test('serializes and hashes deterministic event ids', () {
      const draft = NostrEventDraft(
        pubkey:
            '0000000000000000000000000000000000000000000000000000000000000000',
        createdAt: 0,
        kind: 1,
        tags: [],
        content: '',
      );

      expect(
        draft.serializedForId,
        '[0,"0000000000000000000000000000000000000000000000000000000000000000",0,1,[],""]',
      );
      expect(
        draft.computeId(),
        '2bee8ad7d8d21a7738a41c8c3e71b3f902b5a448b24971c58bd6bff878ee0a3f',
      );
    });

    test(
      'production signer fails closed when native signing is unavailable',
      () {
        const draft = NostrEventDraft(
          pubkey:
              '0000000000000000000000000000000000000000000000000000000000000000',
          createdAt: 0,
          kind: 1,
          tags: [],
          content: '',
        );

        expect(
          UnavailableNostrEventSigner().sign(draft),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('test-only signer rejects dev or stub signatures', () async {
      const draft = NostrEventDraft(
        pubkey:
            '0000000000000000000000000000000000000000000000000000000000000000',
        createdAt: 0,
        kind: 1,
        tags: [],
        content: '',
      );

      await expectLater(
        TestOnlyNostrEventSigner(signatureHex: 'dev-signature').sign(draft),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        TestOnlyNostrEventSigner(signatureHex: 'stub-signature').sign(draft),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
