import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/relay_identity_bootstrap_service.dart';
import 'package:ansible_node/services/relay_handle_store.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('keeps a separate handle for each Relay space', () async {
    const store = SecureRelayHandleStore();
    await store.save('https://relay.elix.cool', 'hcchien.elix.cool');
    await store.save('https://relay.new-elix.cool', 'hcchien2.new-elix.cool');

    expect(await store.load('https://relay.elix.cool'), 'hcchien.elix.cool');
    expect(
      await store.load('https://relay.new-elix.cool'),
      'hcchien2.new-elix.cool',
    );
  });

  test('normalizes a Relay URL to one handle binding', () async {
    const store = SecureRelayHandleStore();
    await store.save('https://RELAY.elix.cool/', 'hcchien.elix.cool');

    expect(await store.load('https://relay.elix.cool'), 'hcchien.elix.cool');
  });

  test(
    're-registers a migrated v1 DID with its canonical genesis proof',
    () async {
      final publicKeyHex = 'ab' * 32;
      final commitment = buildDidElixV1GenesisCommitment(
        genesisKey: publicKeyHex,
        genesisNonceHex: '01' * 32,
      );
      final did = deriveDidElixV1(
        genesisKey: publicKeyHex,
        genesisNonceHex: commitment['genesis_nonce']! as String,
      );
      FlutterSecureStorage.setMockInitialValues({
        'ansible_canonical_did': did,
        'ansible_canonical_handle': 'hcc129.elix.cool',
        'ansible_canonical_public_key': publicKeyHex,
        'ansible_canonical_signing_algorithm': 'ed25519',
        'ansible_canonical_custody': 'reduced_trust',
        'ansible_canonical_genesis_commitment': jsonEncode(commitment),
      });

      var requestCount = 0;
      final signer = _RecordingSigner();
      final client = AtProtoClient(
        baseUrl: 'https://relay.elix.cool',
        client: MockClient((request) async {
          requestCount += 1;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (requestCount == 1) {
            expect(request.url.path, '/api/v2/identity/register');
            expect(body['public_key_hex'], publicKeyHex);
            expect(body['handle_suffix'], 'hcc129');
            return http.Response(
              jsonEncode({
                'nonce': 'relay-nonce-1',
                'expires_at': '2026-08-20T13:00:00Z',
                'handle': 'hcc129.elix.cool',
              }),
              200,
            );
          }

          expect(request.url.path, '/api/v2/identity/anchor');
          expect(body['did'], did);
          expect(body['genesis_commitment'], commitment);
          expect(body['registration_sig'], 'signed-v1-proof');
          return http.Response(
            jsonEncode({
              'did': did,
              'handle': 'hcc129.elix.cool',
              'expires_at': '2026-08-20T13:00:00Z',
            }),
            200,
          );
        }),
      );

      expect(
        await RelayIdentityBootstrapService.ensureVerified(
          did: did,
          baseUrl: 'https://relay.elix.cool',
          signer: signer,
          atProtoClient: client,
        ),
        'hcc129.elix.cool',
      );
      expect(requestCount, 2);
      expect(
        utf8.decode(signer.message!),
        didElixV1RegistrationPayload(
          nonce: 'relay-nonce-1',
          did: did,
          genesisCommitment: commitment,
        ),
      );
    },
  );
}

class _RecordingSigner implements DidSigner {
  List<int>? message;

  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    this.message = List<int>.of(message);
    return const Ed25519Signature('signed-v1-proof');
  }
}
