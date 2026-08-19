import 'dart:convert';
import 'dart:io';

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
  group('did:elix v1 conformance', () {
    const key =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const nonce =
        '0101010101010101010101010101010101010101010101010101010101010101';
    const expected =
        'did:elix:zlg5xyogxphkrhi453x3gxpubfxdveaev6xmgnpcw3zus4653mfyq';

    test('matches the cross-runtime genesis vector exactly', () {
      expect(
        deriveDidElixV1(genesisKey: key, genesisNonceHex: nonce),
        expected,
      );
    });

    test('rejects malformed nonce and changes with genesis input', () {
      expect(
        () => deriveDidElixV1(genesisKey: key, genesisNonceHex: 'AA' * 32),
        throwsArgumentError,
      );
      expect(
        deriveDidElixV1(genesisKey: 'bb' * 32, genesisNonceHex: nonce),
        isNot(expected),
      );
    });

    test('registration proof has fixed nested canonical encoding', () {
      final commitment = buildDidElixV1GenesisCommitment(
        genesisKey: key,
        genesisNonceHex: nonce,
      );
      expect(
        didElixV1RegistrationPayload(
          nonce: 'relay-nonce',
          did: expected,
          genesisCommitment: commitment,
        ),
        '{"type":"io.trisaura.identity.registration","version":1,'
        '"nonce":"relay-nonce","did":"$expected",'
        '"genesis_commitment":{"method":"did:elix","method_version":1,'
        '"genesis_key":"$key","genesis_nonce":"$nonce"}}',
      );
    });

    test('portable vectors cover canonical anchors and the full chain', () {
      final vectors =
          jsonDecode(
                File(
                  '../../docs/architecture/did_elix_v1_conformance_vectors.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final genesis = vectors['genesis'] as Map<String, dynamic>;
      final commitment = (genesis['commitment'] as Map).cast<String, Object?>();

      expect(
        jsonEncode(normalizeDidElixV1GenesisCommitment(commitment)),
        genesis['canonical_commitment'],
      );
      expect(
        deriveDidElixV1(
          genesisKey: commitment['genesis_key']! as String,
          genesisNonceHex: commitment['genesis_nonce']! as String,
        ),
        genesis['did'],
      );

      final registration = vectors['registration'] as Map<String, dynamic>;
      expect(
        didElixV1RegistrationPayload(
          nonce: registration['relay_nonce'] as String,
          did: genesis['did'] as String,
          genesisCommitment: commitment,
        ),
        registration['canonical_payload'],
      );

      final anchors = vectors['anchors'] as Map<String, dynamic>;
      for (final name in ['genesis', 'rotation', 'recovery']) {
        final vector = anchors[name] as Map<String, dynamic>;
        final anchor = IdentityAnchor.fromMap(
          (vector['object'] as Map).cast<String, Object?>(),
        );
        expect(anchor.canonicalBodyJson(), vector['canonical_body']);
        expect(anchor.computeCid(), vector['cid']);
      }

      final chain = (anchors['resolved_chain'] as List)
          .map(
            (value) =>
                IdentityAnchor.fromMap((value as Map).cast<String, Object?>()),
          )
          .toList();
      expect(IdentityAnchorChain.verify(chain).isValid, isTrue);

      final invalid = (vectors['invalid'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (vector) => vector['name'] == 'unknown_commitment_property',
          );
      expect(
        () => normalizeDidElixV1GenesisCommitment(
          (invalid['commitment'] as Map).cast<String, Object?>(),
        ),
        throwsFormatException,
      );
    });

    test('rejects non-canonical public keys', () {
      expect(
        () => deriveDidElixV1(genesisKey: 'AA' * 32, genesisNonceHex: nonce),
        throwsArgumentError,
      );
    });
  });
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
      final a = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'a.elix.cool',
      );
      final b = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'a.elix.cool',
      );
      expect(a, b);
      expect(
        RegExp(r'^did:elix:[a-z2-7]+$').hasMatch(a),
        isTrue,
        reason: 'got $a',
      );
    });

    test('depends on the identity key', () {
      final a = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'a.elix.cool',
      );
      final other = deriveDidElix(
        identityKey: 'aa' * 32,
        handle: 'a.elix.cool',
      );
      expect(a, isNot(other));
    });

    test('depends on the handle', () {
      final a = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'a.elix.cool',
      );
      final b = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'b.elix.cool',
      );
      expect(a, isNot(b));
    });

    test('is not a did:web or did:key', () {
      final d = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'a.elix.cool',
      );
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
      final did = deriveDidElix(
        identityKey: _vectorPubHex,
        handle: 'a.elix.cool',
      );
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
