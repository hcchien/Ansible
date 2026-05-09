import 'package:flutter_test/flutter_test.dart';

import 'fixtures/federation_identity_fixtures.dart';

void main() {
  test('did:plc fixture remains available for current local identity flow', () {
    expect(fixtureDidPlcCompat, startsWith('did:plc:'));
  });

  test('did:nostr fixture represents Nostr public identity', () {
    expect(fixtureDidNostr, 'did:nostr:$fixtureNostrPubkeyHex');
    expect(fixtureNostrPubkeyHex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(fixtureNip05Alias, 'alice@trisaura.io');
  });

  test('ActivityPub actor fixture is canonicalized under relay domain', () {
    final uri = Uri.parse(fixtureActivityPubActor);

    expect(uri.scheme, 'https');
    expect(uri.host, 'relay.trisaura.io');
    expect(uri.path, '/users/alice');
    expect(fixtureActivityPubAcct, 'acct:alice@relay.trisaura.io');
  });
}
