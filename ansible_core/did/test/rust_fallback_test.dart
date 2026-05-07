import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:test/test.dart';

void main() {
  test('Dart fallback emits a relay-compatible local did:plc stub', () async {
    final result = await RustLib.instance.apiCreateDidPlc(
      signingKeyHex: 'ab' * 32,
      handle: 'alice.trisaura.io',
      pdsEndpoint: 'https://trisaura.io',
    );

    expect(result.did, matches(RegExp(r'^did:plc:[a-z2-7]{10,}$')));

    final genesis = jsonDecode(result.genesisJson) as Map<String, dynamic>;
    expect(genesis['stub'], isTrue);
    expect(genesis['type'], 'plc_genesis');
    expect(genesis['signingKey'], isA<String>());
    expect(genesis['rotationKeys'], isA<List>());
    expect(genesis['services'], isA<Map>());
  });
}
