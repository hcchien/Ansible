import 'dart:convert';
import 'dart:io';

import 'package:ansible_node/services/did_elix_resolver.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<({IdentityAnchor anchor, String privateKey})> _v1Genesis(
  String handle,
) async {
  final privateKey = await Ed25519Keys.generateSeedHex();
  final publicKey = await Ed25519Keys.publicKeyHexFromSeed(privateKey);
  final commitment = buildDidElixV1GenesisCommitment(
    genesisKey: publicKey,
    genesisNonceHex: '01' * 32,
  );
  final did = deriveDidElixV1(
    genesisKey: publicKey,
    genesisNonceHex: '01' * 32,
  );
  final unsigned = IdentityAnchor(
    schemaVersion: 4,
    did: did,
    handle: handle,
    identityKey: publicKey,
    genesisCommitment: commitment,
    alsoKnownAs: buildAlsoKnownAs(handle: handle, identityKeyHex: publicKey),
    custodyClass: CustodyClass.software,
    reason: AnchorReason.initial,
    createdAt: DateTime.utc(2026, 8, 19),
    sig: '',
  );
  final signature = await Ed25519Keys.sign(
    privateKey,
    utf8.encode(unsigned.canonicalBodyJson()),
  );
  return (
    privateKey: privateKey,
    anchor: IdentityAnchor(
      schemaVersion: unsigned.schemaVersion,
      did: unsigned.did,
      handle: unsigned.handle,
      identityKey: unsigned.identityKey,
      genesisCommitment: unsigned.genesisCommitment,
      alsoKnownAs: unsigned.alsoKnownAs,
      custodyClass: unsigned.custodyClass,
      reason: unsigned.reason,
      createdAt: unsigned.createdAt,
      sig: signature,
    ),
  );
}

Future<IdentityAnchor> _rotation(
  IdentityAnchor previous,
  String previousPrivateKey,
) async {
  final privateKey = await Ed25519Keys.generateSeedHex();
  final publicKey = await Ed25519Keys.publicKeyHexFromSeed(privateKey);
  final unsigned = IdentityAnchor(
    schemaVersion: 4,
    did: previous.did,
    handle: 'alice-renamed.elix.cool',
    identityKey: publicKey,
    genesisCommitment: previous.genesisCommitment,
    alsoKnownAs: buildAlsoKnownAs(
      handle: 'alice-renamed.elix.cool',
      identityKeyHex: publicKey,
    ),
    custodyClass: CustodyClass.software,
    prevAnchorCid: previous.computeCid(),
    reason: AnchorReason.rotation,
    createdAt: DateTime.utc(2026, 8, 19, 1),
    sig: '',
  );
  final body = utf8.encode(unsigned.canonicalBodyJson());
  return IdentityAnchor(
    schemaVersion: unsigned.schemaVersion,
    did: unsigned.did,
    handle: unsigned.handle,
    identityKey: unsigned.identityKey,
    genesisCommitment: unsigned.genesisCommitment,
    alsoKnownAs: unsigned.alsoKnownAs,
    custodyClass: unsigned.custodyClass,
    prevAnchorCid: unsigned.prevAnchorCid,
    reason: unsigned.reason,
    createdAt: unsigned.createdAt,
    sig: await Ed25519Keys.sign(privateKey, body),
    deviceSig: await Ed25519Keys.sign(previousPrivateKey, body),
  );
}

String _chainJson(List<IdentityAnchor> anchors) {
  return jsonEncode({
    'did': anchors.first.did,
    'anchors': anchors
        .map(
          (anchor) => {
            ...anchor.toCanonicalMap(),
            'anchor_cid': anchor.computeCid(),
            'state': identical(anchor, anchors.last) ? 'active' : 'superseded',
          },
        )
        .toList(),
  });
}

void main() {
  test(
    'resolves a v1 identity after key rotation from the full chain',
    () async {
      final genesis = await _v1Genesis('alice.elix.cool');
      final rotation = await _rotation(genesis.anchor, genesis.privateKey);
      final client = MockClient(
        (_) async => http.Response(_chainJson([genesis.anchor, rotation]), 200),
      );

      final resolver = DidElixResolver(
        relays: ['https://r1.example'],
        client: client,
      );
      final resolved = await resolver.resolve(genesis.anchor.did);

      expect(resolved, isNotNull);
      expect(resolved!.anchor.identityKey, rotation.identityKey);
      expect(resolved.chain, hasLength(2));
      expect(resolved.resolvedVia, 'https://r1.example');
    },
  );

  test(
    'rejects commitment substitution and forged genesis signatures',
    () async {
      final victim = await _v1Genesis('victim.elix.cool');
      final evil = await _v1Genesis('evil.elix.cool');
      final forged = IdentityAnchor(
        schemaVersion: 4,
        did: victim.anchor.did,
        handle: victim.anchor.handle,
        identityKey: evil.anchor.identityKey,
        genesisCommitment: evil.anchor.genesisCommitment,
        alsoKnownAs: evil.anchor.alsoKnownAs,
        custodyClass: CustodyClass.software,
        reason: AnchorReason.initial,
        createdAt: evil.anchor.createdAt,
        sig: evil.anchor.sig,
      );

      final resolver = DidElixResolver(
        relays: ['https://evil.example'],
        client: MockClient(
          (_) async => http.Response(_chainJson([forged]), 200),
        ),
      );
      expect(await resolver.resolve(victim.anchor.did), isNull);
    },
  );

  test(
    'rejects a missing link and a missing previous-authority proof',
    () async {
      final genesis = await _v1Genesis('alice.elix.cool');
      final rotation = await _rotation(genesis.anchor, genesis.privateKey);
      final broken = IdentityAnchor(
        schemaVersion: rotation.schemaVersion,
        did: rotation.did,
        handle: rotation.handle,
        identityKey: rotation.identityKey,
        genesisCommitment: rotation.genesisCommitment,
        alsoKnownAs: rotation.alsoKnownAs,
        custodyClass: rotation.custodyClass,
        prevAnchorCid: 'sha256:${'00' * 32}',
        reason: rotation.reason,
        createdAt: rotation.createdAt,
        sig: rotation.sig,
      );

      for (final candidate in [broken, _withoutAuthorization(rotation)]) {
        final resolver = DidElixResolver(
          relays: ['https://bad.example'],
          client: MockClient(
            (_) async =>
                http.Response(_chainJson([genesis.anchor, candidate]), 200),
          ),
        );
        expect(await resolver.resolve(genesis.anchor.did), isNull);
      }
    },
  );

  test('falls through to the next Relay after unverifiable data', () async {
    final genesis = await _v1Genesis('bob.elix.cool');
    final client = MockClient((request) async {
      if (request.url.host == 'r2.example') {
        return http.Response(_chainJson([genesis.anchor]), 200);
      }
      return http.Response('{"anchors":[]}', 200);
    });

    final resolver = DidElixResolver(
      relays: ['https://r1.example', 'https://r2.example'],
      client: client,
    );
    final resolved = await resolver.resolve(genesis.anchor.did);

    expect(resolved, isNotNull);
    expect(resolved!.resolvedVia, 'https://r2.example');
  });

  test(
    'selects the longest consistent chain across independent Relays',
    () async {
      final genesis = await _v1Genesis('carol.elix.cool');
      final rotation = await _rotation(genesis.anchor, genesis.privateKey);
      final client = MockClient((request) async {
        final chain = request.url.host == 'r1.example'
            ? [genesis.anchor]
            : [genesis.anchor, rotation];
        return http.Response(_chainJson(chain), 200);
      });

      final resolver = DidElixResolver(
        relays: ['https://r1.example', 'https://r2.example'],
        client: client,
      );
      final resolved = await resolver.resolve(genesis.anchor.did);

      expect(resolved, isNotNull);
      expect(resolved!.chain, hasLength(2));
      expect(resolved.anchor.identityKey, rotation.identityKey);
      expect(resolved.resolvedVia, 'https://r2.example');
    },
  );

  test('rejects divergent valid successor chains as equivocation', () async {
    final genesis = await _v1Genesis('fork.elix.cool');
    final first = await _rotation(genesis.anchor, genesis.privateKey);
    final second = await _rotation(genesis.anchor, genesis.privateKey);
    final client = MockClient((request) async {
      final rotation = request.url.host == 'r1.example' ? first : second;
      return http.Response(_chainJson([genesis.anchor, rotation]), 200);
    });

    final resolver = DidElixResolver(
      relays: ['https://r1.example', 'https://r2.example'],
      client: client,
    );

    expect(await resolver.resolve(genesis.anchor.did), isNull);
  });

  test('rejects rollback below an observed active CID checkpoint', () async {
    final genesis = await _v1Genesis('checkpoint.elix.cool');
    final rotation = await _rotation(genesis.anchor, genesis.privateKey);
    var requestCount = 0;
    final resolver = DidElixResolver(
      relays: ['https://r1.example'],
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          _chainJson(
            requestCount == 1 ? [genesis.anchor, rotation] : [genesis.anchor],
          ),
          200,
        );
      }),
    );

    expect((await resolver.resolve(genesis.anchor.did))!.chain, hasLength(2));
    expect(await resolver.resolve(genesis.anchor.did), isNull);
  });

  test('portable invalid anchor vectors all fail closed', () async {
    final vectors =
        jsonDecode(
              File(
                '../../docs/architecture/did_elix_v1_conformance_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final did = (vectors['genesis'] as Map<String, dynamic>)['did'] as String;
    final anchors = vectors['anchors'] as Map<String, dynamic>;
    final genesis = (anchors['genesis'] as Map<String, dynamic>)['object'];
    final rotation = (anchors['rotation'] as Map<String, dynamic>)['object'];
    final invalid = (vectors['invalid'] as List).cast<Map<String, dynamic>>();

    for (final vector in invalid.where((value) => value['anchor'] != null)) {
      final name = vector['name'] as String;
      final candidate = vector['anchor'];
      final chain = switch (name) {
        'commitment_substitution' || 'invalid_signature' => [candidate],
        'fork' => [genesis, rotation, candidate],
        _ => [genesis, candidate],
      };
      final resolver = DidElixResolver(
        relays: ['https://invalid.example'],
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'did': did, 'anchors': chain}), 200),
        ),
      );

      expect(
        await resolver.resolve(did),
        isNull,
        reason: '$name must fail closed',
      );
    }
  });
}

IdentityAnchor _withoutAuthorization(IdentityAnchor anchor) {
  return IdentityAnchor(
    schemaVersion: anchor.schemaVersion,
    did: anchor.did,
    handle: anchor.handle,
    identityKey: anchor.identityKey,
    genesisCommitment: anchor.genesisCommitment,
    alsoKnownAs: anchor.alsoKnownAs,
    custodyClass: anchor.custodyClass,
    prevAnchorCid: anchor.prevAnchorCid,
    reason: anchor.reason,
    createdAt: anchor.createdAt,
    sig: anchor.sig,
  );
}
