import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

// Cross-verified vector: this public key encodes to the did:key below under
// BOTH this pure-Dart encoder and the rust core `encode_did_key` (audited
// `bs58` crate) — confirmed identical, so the wallet holder DID matches the
// production path byte-for-byte.
const _vectorPubHex =
    'b97c30de767f084ce3080168ee293053ba33b235d7116a3263d29f1450936b71';
const _vectorDidKey =
    'did:key:z6MkrwKJd14cfGia7TAWXgAZs7GKyXRhPQqTLnkfiG9YY8VN';

void main() {
  group('encodeDidKeyEd25519', () {
    test('matches the W3C Ed25519 test vector', () {
      expect(encodeDidKeyEd25519(_vectorPubHex), _vectorDidKey);
    });

    test('rejects non-32-byte keys', () {
      expect(() => encodeDidKeyEd25519('00'), throwsArgumentError);
    });
  });

  group('deriveDidElix', () {
    test('is deterministic and well-formed', () {
      final a = deriveDidElix(identityKey: _vectorPubHex, handle: 'a.elix.cool');
      final b = deriveDidElix(identityKey: _vectorPubHex, handle: 'a.elix.cool');
      expect(a, b);
      expect(RegExp(r'^did:elix:[a-z2-7]+$').hasMatch(a), isTrue,
          reason: 'got $a');
    });

    test('depends on the identity key', () {
      final a = deriveDidElix(identityKey: _vectorPubHex, handle: 'a.elix.cool');
      final other = deriveDidElix(identityKey: 'aa' * 32, handle: 'a.elix.cool');
      expect(a, isNot(other));
    });

    test('depends on the handle', () {
      final a = deriveDidElix(identityKey: _vectorPubHex, handle: 'a.elix.cool');
      final b = deriveDidElix(identityKey: _vectorPubHex, handle: 'b.elix.cool');
      expect(a, isNot(b));
    });

    test('is not a did:web or did:key', () {
      final d = deriveDidElix(identityKey: _vectorPubHex, handle: 'a.elix.cool');
      expect(d.startsWith('did:elix:'), isTrue);
    });
  });

  group('buildAlsoKnownAs', () {
    test('includes handle + did:key, omits did:plc by default', () {
      final aka = buildAlsoKnownAs(
        handle: 'a.elix.cool',
        identityKeyHex: _vectorPubHex,
      );
      expect(aka, ['at://a.elix.cool', _vectorDidKey]);
    });

    test('appends did:plc when bridged', () {
      final aka = buildAlsoKnownAs(
        handle: 'a.elix.cool',
        identityKeyHex: _vectorPubHex,
        didPlc: 'did:plc:xyz',
      );
      expect(aka, ['at://a.elix.cool', _vectorDidKey, 'did:plc:xyz']);
    });

    test('never contains a did:web', () {
      final aka = buildAlsoKnownAs(
        handle: 'a.elix.cool',
        identityKeyHex: _vectorPubHex,
        didPlc: 'did:plc:xyz',
      );
      expect(aka.any((a) => a.startsWith('did:web:')), isFalse);
    });
  });

  group('IdentityAnchor v2', () {
    test('carries also_known_as through canonical round-trip', () {
      final aka = buildAlsoKnownAs(
        handle: 'a.elix.cool',
        identityKeyHex: _vectorPubHex,
      );
      final did = deriveDidElix(identityKey: _vectorPubHex, handle: 'a.elix.cool');
      final anchor = IdentityAnchor(
        schemaVersion: 2,
        did: did,
        handle: 'a.elix.cool',
        identityKey: _vectorPubHex,
        alsoKnownAs: aka,
        custodyClass: CustodyClass.software,
        reason: AnchorReason.initial,
        createdAt: DateTime.utc(2026, 6, 16),
        sig: 'deadbeef',
      );
      expect(anchor.schemaVersion, 2);
      final round = IdentityAnchor.fromCanonicalJson(anchor.canonicalJson());
      expect(round.alsoKnownAs, aka);
      expect(round.did, did);
      expect(round.computeCid(), anchor.computeCid());
    });
  });
}
