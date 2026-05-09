import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:test/test.dart';

void main() {
  group('NIP-19 identifiers', () {
    test('encodes and decodes npub identifiers', () {
      final pubkey = 'f' * 64;

      final npub = NostrIdentifier.encodeNpub(pubkey);
      expect(
        npub,
        'npub1lllllllllllllllllllllllllllllllllllllllllllllllllllsq7lrjw',
      );
      expect(NostrIdentifier.decodeNpub(npub), pubkey);
    });

    test('encodes and decodes note identifiers', () {
      final eventId = 'a' * 64;

      final note = NostrIdentifier.encodeNote(eventId);
      expect(
        note,
        'note1424242424242424242424242424242424242424242424242424qv3q9y6',
      );
      expect(NostrIdentifier.decodeNote(note), eventId);
    });

    test('encodes nevent and naddr display identifiers', () {
      final eventId = 'a' * 64;
      final pubkey = 'f' * 64;

      final nevent = NostrIdentifier.encodeNevent(
        eventId,
        relays: ['wss://relay.example'],
        authorPubkeyHex: pubkey,
        kind: 1,
      );
      final naddr = NostrIdentifier.encodeNaddr(
        identifier: 'note-title',
        pubkeyHex: pubkey,
        kind: 30023,
        relays: ['wss://relay.example'],
      );

      expect(nevent, startsWith('nevent1'));
      expect(naddr, startsWith('naddr1'));
    });

    test('rejects identifiers with the wrong human-readable prefix', () {
      final note = NostrIdentifier.encodeNote('a' * 64);

      expect(() => NostrIdentifier.decodeNpub(note), throwsArgumentError);
    });
  });
}
