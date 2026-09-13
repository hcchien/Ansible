import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/sync_capability_service.dart';
import 'package:ansible_node/services/platform_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'enrolls and authorizes without contacting an unavailable Viewer',
    () async {
      final paths = <String>[];
      final bodies = <Map<String, dynamic>>[];
      final platform = _FakeWebAuthnPlatform();
      final client = MockClient((request) async {
        expect(request.url.host, 'relay.example');
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
              'origin': 'https://elix.cool',
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
          case '/api/v2/webauthn/credentials/Y3JlZA/revoke':
            return _json({'revoked': true});
          case '/api/v2/webauthn/authenticate/exchange':
            return _json({
              'token': 'capability-token',
              'expires_in': 300,
              'scope': ['sync:write'],
            });
        }
        return http.Response('not found', 404);
      });

      final service = SyncCapabilityService(
        baseUrl: 'https://relay.example',
        holderDid: 'did:elix:alice',
        platform: platform,
        didSigner: _FakeDidSigner(),
        client: client,
        now: () => DateTime.utc(2026, 7, 21),
      );
      final capability = await service.authorize();

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
      final delegation = finish['delegation'] as Map<String, dynamic>;
      expect(delegation['subject_did'], 'did:elix:alice');
      expect(delegation['rp_id'], 'elix.cool');
      expect(delegation['issued_at'], '2026-07-21T00:00:00.000Z');
      expect(delegation['expires_at'], '2026-10-19T00:00:00.000Z');
      expect(
        delegation['allowed_actions'],
        containsAll([
          'forum.publish',
          'forum.reply',
          'forum.edit',
          'forum.delete',
          'forum.react',
        ]),
      );
      await service.revokeSavedWebCredentials();
      expect(paths, contains('/api/v2/webauthn/credentials/Y3JlZA/revoke'));
    },
  );

  test(
    'relay revoke failure preserves retry without contacting a Viewer',
    () async {
      final key =
          'elix.web.credentials.${sha256.convert(utf8.encode('did:elix:alice\u0000https://relay.example'))}';
      SharedPreferences.setMockInitialValues({
        key: ['Y3JlZA'],
      });
      var available = false;
      final hosts = <String>[];
      final service = SyncCapabilityService(
        baseUrl: 'https://relay.example',
        holderDid: 'did:elix:alice',
        didSigner: _FakeDidSigner(),
        platform: _FakeWebAuthnPlatform(),
        client: MockClient((request) async {
          hosts.add(request.url.host);
          expect(
            request.url.path,
            '/api/v2/webauthn/credentials/Y3JlZA/revoke',
          );
          return available
              ? _json({'revoked': true})
              : http.Response('{"error":"unavailable"}', 503);
        }),
      );
      await expectLater(
        service.revokeSavedWebCredentials(),
        throwsA(isA<SyncCapabilityException>()),
      );
      expect((await SharedPreferences.getInstance()).getStringList(key), [
        'Y3JlZA',
      ]);
      available = true;
      await service.revokeSavedWebCredentials();
      expect(hosts, ['relay.example', 'relay.example']);
      expect(
        (await SharedPreferences.getInstance()).getStringList(key),
        isEmpty,
      );
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

  test('coalesces concurrent authorization into one passkey prompt', () async {
    final platform = _FakeWebAuthnPlatform();
    var optionCalls = 0;
    var exchangeCalls = 0;
    final service = SyncCapabilityService(
      baseUrl: 'https://relay.example',
      holderDid: 'did:elix:alice',
      platform: platform,
      didSigner: _FakeDidSigner(),
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/v2/webauthn/authenticate/options':
            optionCalls += 1;
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
          case '/api/v2/webauthn/authenticate/exchange':
            exchangeCalls += 1;
            return _json({'token': 'capability-token', 'expires_in': 300});
        }
        return http.Response('not found', 404);
      }),
      now: () => DateTime.utc(2026, 7, 27),
    );

    final capabilities = await Future.wait([
      service.authorize(),
      service.authorize(),
    ]);

    expect(
      capabilities.map((item) => item.token),
      everyElement('capability-token'),
    );
    expect(optionCalls, 1);
    expect(exchangeCalls, 1);
    expect(platform.authenticateCalls, 1);

    final cached = await service.authorize();
    expect(cached.token, 'capability-token');
    expect(platform.authenticateCalls, 1);
  });

  test(
    'reports an empty Relay response without leaking a JSON parser error',
    () async {
      final service = SyncCapabilityService(
        baseUrl: 'https://relay.example',
        holderDid: 'did:elix:alice',
        platform: _FakeWebAuthnPlatform(),
        didSigner: _FakeDidSigner(),
        client: MockClient((_) async => http.Response('', 502)),
      );

      await expectLater(
        service.authorize(),
        throwsA(
          isA<SyncCapabilityException>()
              .having((error) => error.statusCode, 'statusCode', 502)
              .having((error) => error.error, 'error', 'webauthn_error'),
        ),
      );
    },
  );

  test('Linux fails closed before attempting unsupported WebAuthn', () async {
    var called = false;
    final service = SyncCapabilityService(
      baseUrl: 'https://relay.example',
      holderDid: 'did:elix:alice',
      platformCapabilities: PlatformCapabilities.forPlatform(
        ElixPlatform.linux,
      ),
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 500);
      }),
    );

    await expectLater(
      service.authorize(),
      throwsA(
        isA<SyncCapabilityException>().having(
          (error) => error.error,
          'error',
          'webauthn_unavailable',
        ),
      ),
    );
    expect(called, isFalse);
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
    final delegation = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    if (delegation['type'] == 'io.trisaura.identity.webCredentialRevocation') {
      expect(delegation['credential_id'], 'Y3JlZA');
      expect(delegation['nonce'], isNotEmpty);
    } else {
      expect(
        delegation['type'],
        'io.trisaura.identity.webCredentialDelegation',
      );
      expect(delegation['challenge_id'], 'register-1');
      expect(delegation['credential_id_hash'], isNotEmpty);
    }
    return Ed25519Signature('aa' * 64);
  }
}
