import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/sync_capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'enrolls a passkey then exchanges an assertion for a capability',
    () async {
      final paths = <String>[];
      final bodies = <Map<String, dynamic>>[];
      final platform = _FakeWebAuthnPlatform();
      final client = MockClient((request) async {
        paths.add(request.url.path);
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        switch (request.url.path) {
          case '/api/v2/webauthn/authenticate/options':
            final attempts = paths
                .where((path) => path.endsWith('/authenticate/options'))
                .length;
            if (attempts == 1) {
              return http.Response(
                jsonEncode({'error': 'passkey_not_enrolled'}),
                409,
              );
            }
            return _json({
              'challenge_id': 'auth-1',
              'publicKey': {
                'challenge': 'YXV0aA',
                'rpId': 'elix.cool',
                'allowCredentials': [
                  {'type': 'public-key', 'id': 'Y3JlZA'},
                ],
                'userVerification': 'required',
              },
            });
          case '/api/v2/webauthn/register/options':
            return _json({
              'challenge_id': 'register-1',
              'publicKey': {
                'challenge': 'cmVnaXN0ZXI',
                'rp': {'id': 'elix.cool', 'name': 'Elix'},
                'user': {
                  'id': 'dXNlcg',
                  'name': 'did:elix:alice',
                  'displayName': 'Alice',
                },
                'excludeCredentials': <Object?>[],
              },
            });
          case '/api/v2/webauthn/register/finish':
            return _json({'enrolled': true}, status: 201);
          case '/api/v2/webauthn/authenticate/exchange':
            return _json({
              'token': 'capability-token',
              'expires_in': 300,
              'scope': ['sync:write'],
            });
        }
        return http.Response('not found', 404);
      });

      final capability = await SyncCapabilityService(
        baseUrl: 'https://relay.example',
        holderDid: 'did:elix:alice',
        platform: platform,
        didSigner: _FakeDidSigner(),
        client: client,
        now: () => DateTime.utc(2026, 7, 21),
      ).authorize();

      expect(capability.token, 'capability-token');
      expect(platform.registerCalls, 1);
      expect(platform.authenticateCalls, 1);
      expect(
        paths,
        containsAllInOrder([
          '/api/v2/webauthn/authenticate/options',
          '/api/v2/webauthn/register/options',
          '/api/v2/webauthn/register/finish',
          '/api/v2/webauthn/authenticate/options',
          '/api/v2/webauthn/authenticate/exchange',
        ]),
      );
      final finish = bodies[2];
      expect(finish['did_signature'], 'aa' * 64);
      expect(finish['challenge_id'], 'register-1');
    },
  );

  test('does not silently enroll when enrollment is disabled', () async {
    final service = SyncCapabilityService(
      baseUrl: 'https://relay.example',
      holderDid: 'did:elix:alice',
      platform: _FakeWebAuthnPlatform(),
      didSigner: _FakeDidSigner(),
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'passkey_not_enrolled'}), 409),
      ),
    );

    await expectLater(
      service.authorize(allowEnrollment: false),
      throwsA(isA<SyncCapabilityException>()),
    );
  });
}

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

class _FakeWebAuthnPlatform implements WebAuthnPlatform {
  int registerCalls = 0;
  int authenticateCalls = 0;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    registerCalls += 1;
    expect(options['challenge'], 'cmVnaXN0ZXI');
    return {
      'id': 'Y3JlZA',
      'rawId': 'Y3JlZA',
      'type': 'public-key',
      'response': {
        'clientDataJSON': 'Y2xpZW50',
        'attestationObject': 'YXR0ZXN0YXRpb24',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> options,
  ) async {
    authenticateCalls += 1;
    expect(options['userVerification'], 'required');
    return {
      'id': 'Y3JlZA',
      'rawId': 'Y3JlZA',
      'type': 'public-key',
      'response': {
        'clientDataJSON': 'Y2xpZW50',
        'authenticatorData': 'YXV0aGRhdGE',
        'signature': 'c2lnbmF0dXJl',
      },
    };
  }
}

class _FakeDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    expect(utf8.decode(message), 'register-1.Y3JlZA');
    return Ed25519Signature('aa' * 64);
  }
}
