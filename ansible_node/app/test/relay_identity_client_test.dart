import 'dart:convert';

import 'package:ansible_node/services/relay_identity_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchPublicKey reads the verified key for a registered DID', () async {
    final client = RelayIdentityClient(
      baseUrl: 'http://relay.local/root',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'http://relay.local/root/api/v1/identity/public-key/did%3Akey%3Az6MkTest',
        );
        return http.Response(
          jsonEncode({'did': 'did:key:z6MkTest', 'public_key_hex': 'abcd'}),
          200,
        );
      }),
    );

    expect(await client.fetchPublicKey('did:key:z6MkTest'), 'abcd');
  });

  test('fetchPublicKey returns null for an unregistered DID (404)', () async {
    final client = RelayIdentityClient(
      client: MockClient((_) async => http.Response('{}', 404)),
    );

    expect(await client.fetchPublicKey('did:key:z6MkUnknown'), isNull);
  });

  test('fetchPublicKey surfaces relay errors as typed exceptions', () async {
    final client = RelayIdentityClient(
      client: MockClient((_) async => http.Response('boom', 500)),
    );

    expect(
      () => client.fetchPublicKey('did:key:z6MkTest'),
      throwsA(
        isA<RelayIdentityException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.error, 'error', 'public_key_fetch_failed'),
      ),
    );
  });

  test('fetchPublicKey preserves a retryable identity service error', () async {
    final client = RelayIdentityClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'verification_unavailable', 'retryable': true}),
          503,
        ),
      ),
    );

    expect(
      () => client.fetchPublicKey('did:elix:test'),
      throwsA(
        isA<RelayIdentityException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.error, 'error', 'verification_unavailable'),
      ),
    );
  });
}
