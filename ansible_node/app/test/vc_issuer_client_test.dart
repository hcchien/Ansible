import 'dart:convert';

import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('VcIssuerClient.requestEmailVerification', () {
    test('posts did and email to /api/v1/vc/request', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.local',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://issuer.local/api/v1/vc/request',
          );
          expect(request.headers['content-type'], 'application/json');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['did'], 'did:key:z6MkTest');
          expect(body['email'], 'user@example.com');

          return http.Response(
            jsonEncode({'hint': 'OTP sent', 'otp': '123456'}),
            200,
          );
        }),
      );

      final challenge = await client.requestEmailVerification(
        did: 'did:key:z6MkTest',
        email: 'user@example.com',
      );

      expect(challenge.hint, 'OTP sent');
      expect(challenge.otp, '123456');
      expect(challenge.isMockOtp, isTrue);
    });

    test('isMockOtp is false when otp is absent from response', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.local',
        client: MockClient((_) async {
          return http.Response(jsonEncode({'hint': 'Check your inbox'}), 200);
        }),
      );

      final challenge = await client.requestEmailVerification(
        did: 'did:key:z6MkTest',
        email: 'user@example.com',
      );

      expect(challenge.isMockOtp, isFalse);
      expect(challenge.otp, isNull);
      expect(challenge.hint, 'Check your inbox');
    });

    test('throws VcIssuerException on non-2xx response', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.local',
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'rate_limited'}), 429);
        }),
      );

      expect(
        () => client.requestEmailVerification(
          did: 'did:key:z6MkTest',
          email: 'user@example.com',
        ),
        throwsA(
          isA<VcIssuerException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.error, 'error', 'rate_limited'),
        ),
      );
    });
  });

  group('VcIssuerClient.issueCredential', () {
    test(
      'posts did, email, and otp to /api/v1/vc/issue and returns vc map',
      () async {
        final vcFixture = <String, dynamic>{
          'id': 'urn:uuid:issued-vc',
          'type': ['VerifiableCredential', 'EmailCredential'],
          'issuer': 'did:web:issuer.elix.cool',
        };

        final client = VcIssuerClient(
          baseUrl: 'http://issuer.local',
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(
              request.url.toString(),
              'http://issuer.local/api/v1/vc/issue',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['did'], 'did:key:z6MkTest');
            expect(body['email'], 'user@example.com');
            expect(body['otp'], '123456');

            return http.Response(jsonEncode({'vc': vcFixture}), 200);
          }),
        );

        final vc = await client.issueCredential(
          did: 'did:key:z6MkTest',
          email: 'user@example.com',
          otp: '123456',
        );

        expect(vc['id'], 'urn:uuid:issued-vc');
        expect(vc['issuer'], 'did:web:issuer.elix.cool');
      },
    );

    test('throws VcIssuerException on invalid OTP', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.local',
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'invalid_otp'}), 422);
        }),
      );

      expect(
        () => client.issueCredential(
          did: 'did:key:z6MkTest',
          email: 'user@example.com',
          otp: 'wrong',
        ),
        throwsA(
          isA<VcIssuerException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.error, 'error', 'invalid_otp'),
        ),
      );
    });

    test('handles base URL with trailing slash', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.local/',
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://issuer.local/api/v1/vc/issue');
          return http.Response(jsonEncode({'vc': <String, dynamic>{}}), 200);
        }),
      );

      final vc = await client.issueCredential(
        did: 'did:key:z6MkTest',
        email: 'user@example.com',
        otp: '000000',
      );

      expect(vc, isA<Map<String, dynamic>>());
    });
  });

  group('VcIssuerClient TW provider flow', () {
    test(
      'startTwProviderFlow posts did and email to /api/v1/vc/tw/start',
      () async {
        final client = VcIssuerClient(
          baseUrl: 'http://issuer.test',
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/vc/tw/start');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['did'], 'did:plc:abcdefghijklmnop');
            expect(body['email'], 'alice@example.com');
            return http.Response(
              jsonEncode({
                'offer_id': 'offer-1',
                'state': 'state-1',
                'authorization_url':
                    'https://provider.example/authorize?state=state-1',
                'expires_at': '2026-05-05T12:05:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final offer = await client.startTwProviderFlow(
          did: 'did:plc:abcdefghijklmnop',
          email: 'alice@example.com',
        );

        expect(offer.offerId, 'offer-1');
        expect(offer.authorizationUrl.toString(), contains('state-1'));
      },
    );

    test('getTwProviderStatus gets /api/v1/vc/tw/status/{offerId}', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.test',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/vc/tw/status/offer-1');
          return http.Response(jsonEncode({'status': 'verified'}), 200);
        }),
      );

      final status = await client.getTwProviderStatus('offer-1');

      expect(status.status, 'verified');
      expect(status.isVerified, isTrue);
    });

    test(
      'issueTwProviderCredential posts offer id to /api/v1/vc/tw/issue',
      () async {
        final client = VcIssuerClient(
          baseUrl: 'http://issuer.test',
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/vc/tw/issue');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['offer_id'], 'offer-1');
            return http.Response(
              jsonEncode({
                'vc': {'id': 'vc-1'},
              }),
              200,
            );
          }),
        );

        final vc = await client.issueTwProviderCredential(
          did: 'did:plc:abcdefghijklmnop',
          email: 'alice@example.com',
          offerId: 'offer-1',
        );

        expect(vc['id'], 'vc-1');
      },
    );
  });

  group('VcIssuerClient MobileMoica RP flow', () {
    test(
      'startMobileMoicaRPFlow posts disclosure fields without email',
      () async {
        final client = VcIssuerClient(
          baseUrl: 'http://issuer.test',
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/vc/mobilemoica/start');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['holder_did'], 'did:plc:abcdefghijklmnop');
            expect(body['national_id'], 'Z123000000');
            expect(body['consent_version'], 'mobilemoica-rp-v1');
            expect(body['consent_copy_hash'], 'sha256:copy-hash');
            expect(body['locale'], 'zh-Hant-TW');
            expect(body.keys, isNot(contains('email')));
            return http.Response(
              jsonEncode({
                'offer_id': 'offer-1',
                'expires_at': '2026-05-30T12:05:00Z',
                'deep_link_url':
                    'mobilemoica://moica.moi.gov.tw/a2a/verifySign?sp_ticket=contract',
              }),
              200,
            );
          }),
        );

        final offer = await client.startMobileMoicaRPFlow(
          holderDid: 'did:plc:abcdefghijklmnop',
          nationalId: 'Z123000000',
          consentVersion: 'mobilemoica-rp-v1',
          consentCopyHash: 'sha256:copy-hash',
          locale: 'zh-Hant-TW',
        );

        expect(offer.offerId, 'offer-1');
        expect(offer.deepLinkUrl.scheme, 'mobilemoica');
      },
    );

    test('getMobileMoicaRPStatus gets status endpoint', () async {
      final client = VcIssuerClient(
        baseUrl: 'http://issuer.test',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/vc/mobilemoica/status/offer-1');
          return http.Response(
            jsonEncode({
              'status': 'verified',
              'assurance_method': 'mobilemoica_rp_explicit_disclosure',
              'jurisdiction': 'TW',
            }),
            200,
          );
        }),
      );

      final status = await client.getMobileMoicaRPStatus('offer-1');

      expect(status.status, 'verified');
      expect(status.isVerified, isTrue);
    });

    test(
      'issueMobileMoicaRPCredential posts holder did and offer id only',
      () async {
        final client = VcIssuerClient(
          baseUrl: 'http://issuer.test',
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/vc/mobilemoica/issue');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body, {
              'holder_did': 'did:plc:abcdefghijklmnop',
              'offer_id': 'offer-1',
            });
            expect(body.keys, isNot(contains('email')));
            expect(body.keys, isNot(contains('national_id')));
            return http.Response(
              jsonEncode({
                'vc': {'id': 'mobilemoica-vc-1'},
              }),
              200,
            );
          }),
        );

        final vc = await client.issueMobileMoicaRPCredential(
          holderDid: 'did:plc:abcdefghijklmnop',
          offerId: 'offer-1',
        );

        expect(vc['id'], 'mobilemoica-vc-1');
      },
    );
  });

  group('VcIssuerClient passport challenge', () {
    test('requests a DID-bound, short-lived ZKPassport challenge', () async {
      final client = VcIssuerClient(
        baseUrl: 'https://issuer-dev.elix.cool',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/vc/passport/challenges');
          expect(jsonDecode(request.body), {'did': 'did:plc:abcdefghijklmnop'});
          return http.Response(
            jsonEncode({
              'challenge_id': 'challenge-1',
              'nonce': 'nonce-1',
              'issuer': 'https://issuer-dev.elix.cool',
              'scope': 'elix-passport-personhood-v1',
              'circuit_manifest_version': '0.20.0',
              'expires_at': '2026-07-23T04:05:00Z',
            }),
            201,
          );
        }),
      );

      final challenge = await client.requestPassportChallenge(
        did: 'did:plc:abcdefghijklmnop',
      );
      expect(challenge.challengeId, 'challenge-1');
      expect(challenge.nonce, 'nonce-1');
      expect(challenge.issuer.host, 'issuer-dev.elix.cool');
      expect(challenge.scope, 'elix-passport-personhood-v1');
      expect(challenge.circuitManifestVersion, '0.20.0');
    });
  });

  group('VcIssuerClient passport flow', () {
    test(
      'issuePassportCredential posts personhood hashes and proof fields',
      () async {
        final client = VcIssuerClient(
          baseUrl: 'http://issuer.test',
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/vc/passport/issue');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body, {
              'did': 'did:plc:abcdefghijklmnop',
              'challenge_id': 'challenge-1',
              'challenge_nonce': 'nonce-1',
              'nationality': 'TWN',
              'national_id_hash': 'national-id-hash-abc123',
              'passport_number_hash': 'passport-number-hash-abc123',
              'zkp_proof': 'proof-abc123',
              'zkp_circuit_version': 'passport_v1_groth16_bn254',
              'verification_key_hash': 'sha256:vk-hash-abc123',
            });
            expect(body.keys, isNot(contains('verified')));
            expect(body.keys, isNot(contains('passport_uid')));
            expect(body.keys, isNot(contains('documentNumber')));
            expect(body.keys, isNot(contains('passportLocalUniqueId')));
            return http.Response(
              jsonEncode({
                'credentials': [
                  {'id': 'passport-humanity-vc-1'},
                  {'id': 'passport-nationality-vc-1'},
                  {'id': 'passport-age-vc-1'},
                ],
              }),
              200,
            );
          }),
        );

        final vc = await client.issuePassportCredential(
          did: 'did:plc:abcdefghijklmnop',
          challengeId: 'challenge-1',
          challengeNonce: 'nonce-1',
          nationality: 'TWN',
          nationalIdHash: 'national-id-hash-abc123',
          passportNumberHash: 'passport-number-hash-abc123',
          zkpProof: 'proof-abc123',
          zkpCircuitVersion: 'passport_v1_groth16_bn254',
          verificationKeyHash: 'sha256:vk-hash-abc123',
        );

        expect(vc.map((item) => item['id']), [
          'passport-humanity-vc-1',
          'passport-nationality-vc-1',
          'passport-age-vc-1',
        ]);
      },
    );
  });
}
