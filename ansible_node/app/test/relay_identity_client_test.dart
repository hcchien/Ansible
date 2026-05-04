import 'dart:convert';

import 'package:ansible_node/services/relay_identity_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'issueChallenge posts the DID to the relay challenge endpoint',
    () async {
      final client = RelayIdentityClient(
        baseUrl: 'http://relay.local/root',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://relay.local/root/api/v1/identity/challenge',
          );
          expect(request.headers['content-type'], 'application/json');
          expect(jsonDecode(request.body), {'did': 'did:key:z6MkTest'});

          return http.Response(
            jsonEncode({
              'did': 'did:key:z6MkTest',
              'challenge': 'nonce-1',
              'expires_at': '2026-05-02T00:00:00Z',
            }),
            200,
          );
        }),
      );

      final challenge = await client.issueChallenge('did:key:z6MkTest');

      expect(challenge.did, 'did:key:z6MkTest');
      expect(challenge.challenge, 'nonce-1');
    },
  );

  test('anchor sends the Phase 1 envelope expected by the relay', () async {
    final client = RelayIdentityClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/identity/anchor');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['did'], 'did:key:z6MkTest');
        expect(body['zkp_circuit_version'], kDevZkpCircuitVersion);
        expect(body['verification_key_hash'], kDevVerificationKeyHash);
        expect(body['challenge'], 'nonce-1');
        expect(body['challenge_signature'], 'signature-hex');

        return http.Response(
          jsonEncode({
            'verified': true,
            'did': 'did:key:z6MkTest',
            'expires_at': '2026-08-01T00:00:00Z',
          }),
          200,
        );
      }),
    );

    final result = await client.anchor(
      const IdentityAnchorRequest(
        did: 'did:key:z6MkTest',
        zkpProof: 'dev-proof',
        zkpCircuitVersion: kDevZkpCircuitVersion,
        verificationKeyHash: kDevVerificationKeyHash,
        nullifier: 'dev-nullifier',
        publicKeyHex: '00',
        challenge: 'nonce-1',
        challengeSignatureHex: 'signature-hex',
      ),
    );

    expect(result.verified, isTrue);
    expect(result.did, 'did:key:z6MkTest');
  });

  test('relay errors are exposed as typed exceptions', () async {
    final client = RelayIdentityClient(
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': 'duplicate_nullifier',
            'message': 'This passport has already been used.',
          }),
          409,
        );
      }),
    );

    expect(
      () => client.anchor(
        const IdentityAnchorRequest(
          did: 'did:key:z6MkTest',
          zkpProof: 'dev-proof',
          zkpCircuitVersion: kDevZkpCircuitVersion,
          verificationKeyHash: kDevVerificationKeyHash,
          nullifier: 'dev-nullifier',
          publicKeyHex: '00',
          challenge: 'nonce-1',
          challengeSignatureHex: 'signature-hex',
        ),
      ),
      throwsA(
        isA<RelayIdentityException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.error, 'error', 'duplicate_nullifier'),
      ),
    );
  });
}
