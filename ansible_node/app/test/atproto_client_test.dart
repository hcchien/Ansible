import 'dart:convert';

import 'package:ansible_node/services/atproto_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'register posts the passkeys public key field expected by the relay',
    () async {
      final client = AtProtoClient(
        baseUrl: 'http://relay.local/root',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://relay.local/root/api/v2/identity/register',
          );
          expect(request.headers['content-type'], 'application/json');
          expect(jsonDecode(request.body), {
            'public_key_hex': '00' * 32,
            'handle_suffix': 'alice',
          });

          return http.Response(
            jsonEncode({
              'nonce': 'nonce-1',
              'expires_at': '2026-05-04T00:00:00Z',
              'handle': 'alice.trisaura.io',
            }),
            200,
          );
        }),
      );

      final challenge = await client.register(
        publicKeyHex: '00' * 32,
        handleSuffix: 'alice',
      );

      expect(challenge.nonce, 'nonce-1');
      expect(challenge.expiresAt, '2026-05-04T00:00:00Z');
      expect(challenge.handle, 'alice.trisaura.io');
    },
  );

  test(
    'anchor sends did, public key, nonce, and registration signature',
    () async {
      final client = AtProtoClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v2/identity/anchor');
          expect(jsonDecode(request.body), {
            'did': 'did:plc:test',
            'public_key_hex': '11' * 32,
            'handle': 'alice.trisaura.io',
            'registration_sig': 'sig-hex',
            'nonce': 'nonce-1',
          });

          return http.Response(
            jsonEncode({
              'did': 'did:plc:test',
              'handle': 'alice.trisaura.io',
              'expires_at': '2026-08-04T00:00:00Z',
            }),
            200,
          );
        }),
      );

      final anchored = await client.anchor(
        AnchorRequest(
          did: 'did:plc:test',
          publicKeyHex: '11' * 32,
          handle: 'alice.trisaura.io',
          registrationSig: 'sig-hex',
          nonce: 'nonce-1',
        ),
      );

      expect(anchored.did, 'did:plc:test');
      expect(anchored.handle, 'alice.trisaura.io');
    },
  );

  test('relay errors are exposed as typed AT Protocol exceptions', () async {
    final client = AtProtoClient(
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': 'handle_taken',
            'message': 'Handle is already registered.',
          }),
          409,
        );
      }),
    );

    expect(
      () => client.register(publicKeyHex: '22' * 32, handleSuffix: 'alice'),
      throwsA(
        isA<AtProtoException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.error, 'error', 'handle_taken')
            .having(
              (e) => e.message,
              'message',
              'Handle is already registered.',
            ),
      ),
    );
  });

  test(
    'resolveHandle returns the DID from AT Protocol XRPC response',
    () async {
      final client = AtProtoClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/xrpc/com.atproto.identity.resolveHandle');
          expect(request.url.queryParameters, {'handle': 'alice.trisaura.io'});

          return http.Response(jsonEncode({'did': 'did:plc:alice'}), 200);
        }),
      );

      expect(await client.resolveHandle('alice.trisaura.io'), 'did:plc:alice');
    },
  );

  test('presentVp includes an optional Nostr binding payload', () async {
    final client = AtProtoClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v2/reputation/present');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['holder_did'], 'did:plc:alice');
        expect(body['vp'], {'holder': 'did:plc:alice'});
        expect(body['nostr_binding'], {
          'event': {'pubkey': 'b' * 64},
        });

        return http.Response(
          jsonEncode({'reputation_tier': 'verified_human'}),
          200,
        );
      }),
    );

    final tier = await client.presentVp(
      holderDid: 'did:plc:alice',
      vp: {'holder': 'did:plc:alice'},
      nostrBinding: {
        'event': {'pubkey': 'b' * 64},
      },
    );

    expect(tier, 'verified_human');
  });
}
