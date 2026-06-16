import 'dart:convert';

import 'package:ansible_node/services/did_elix_resolver.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Build a fully-signed, self-certifying genesis anchor and its served JSON.
Future<({String did, String json})> _signedAnchor(String handle) async {
  final priv = await Ed25519Keys.generateSeedHex();
  final pub = await Ed25519Keys.publicKeyHexFromSeed(priv);
  final did = deriveDidElix(identityKey: pub, handle: handle);

  final unsigned = IdentityAnchor(
    did: did,
    handle: handle,
    identityKey: pub,
    alsoKnownAs: buildAlsoKnownAs(handle: handle, identityKeyHex: pub),
    custodyClass: CustodyClass.software,
    reason: AnchorReason.initial,
    createdAt: DateTime.utc(2026, 6, 16),
    sig: '',
  );
  final sig = await Ed25519Keys.sign(priv, utf8.encode(unsigned.canonicalBodyJson()));

  final anchor = IdentityAnchor(
    did: did,
    handle: handle,
    identityKey: pub,
    alsoKnownAs: unsigned.alsoKnownAs,
    custodyClass: CustodyClass.software,
    reason: AnchorReason.initial,
    createdAt: unsigned.createdAt,
    sig: sig,
  );
  return (did: did, json: anchor.canonicalJson());
}

void main() {
  test('resolves and verifies a self-certifying anchor', () async {
    final a = await _signedAnchor('alice.elix.cool');
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/identity/anchor/${a.did}') {
        return http.Response(a.json, 200);
      }
      return http.Response('{}', 404);
    });

    final resolver = DidElixResolver(relays: ['https://r1.example'], client: client);
    final resolved = await resolver.resolve(a.did);

    expect(resolved, isNotNull);
    expect(resolved!.anchor.did, a.did);
    expect(resolved.resolvedVia, 'https://r1.example');
    expect(resolved.didKey, startsWith('did:key:'));
  });

  test('rejects a forged anchor served under a victim DID', () async {
    // Victim DID.
    final victim = await _signedAnchor('victim.elix.cool');

    // A forged anchor: a DIFFERENT key signs an anchor claiming the victim DID.
    final evilPriv = await Ed25519Keys.generateSeedHex();
    final evilPub = await Ed25519Keys.publicKeyHexFromSeed(evilPriv);
    final unsigned = IdentityAnchor(
      did: victim.did,
      handle: 'victim.elix.cool',
      identityKey: evilPub,
      alsoKnownAs: buildAlsoKnownAs(handle: 'victim.elix.cool', identityKeyHex: evilPub),
      custodyClass: CustodyClass.software,
      reason: AnchorReason.initial,
      createdAt: DateTime.utc(2026, 6, 16),
      sig: '',
    );
    final evilSig = await Ed25519Keys.sign(evilPriv, utf8.encode(unsigned.canonicalBodyJson()));
    final forged = IdentityAnchor(
      did: victim.did,
      handle: 'victim.elix.cool',
      identityKey: evilPub,
      alsoKnownAs: unsigned.alsoKnownAs,
      custodyClass: CustodyClass.software,
      reason: AnchorReason.initial,
      createdAt: unsigned.createdAt,
      sig: evilSig,
    ).canonicalJson();

    final client = MockClient((req) async => http.Response(forged, 200));
    final resolver = DidElixResolver(relays: ['https://evil.example'], client: client);

    expect(await resolver.resolve(victim.did), isNull);
  });

  test('falls through to the next relay when the first 404s', () async {
    final a = await _signedAnchor('bob.elix.cool');
    final client = MockClient((req) async {
      if (req.url.host == 'r2.example' &&
          req.url.path == '/api/v1/identity/anchor/${a.did}') {
        return http.Response(a.json, 200);
      }
      return http.Response('{}', 404);
    });

    final resolver = DidElixResolver(
      relays: ['https://r1.example', 'https://r2.example'],
      client: client,
    );
    final resolved = await resolver.resolve(a.did);

    expect(resolved, isNotNull);
    expect(resolved!.resolvedVia, 'https://r2.example');
  });
}
