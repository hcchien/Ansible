import 'dart:convert';

import 'package:ansible_node/services/web_session_approval_client.dart';
import 'package:ansible_node/services/web_session_grant_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchChallenge reads relay challenge metadata', () async {
    final client = WebSessionApprovalClient(
      baseUrl: 'http://relay.local/root',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'http://relay.local/root/api/v1/web-sessions/challenges/wsc_abc',
        );
        return http.Response(
          jsonEncode({
            'challenge_id': 'wsc_abc',
            'relay_origin': 'https://relay.trisaura.io',
            'web_origin': 'https://trisaura.io',
            'scopes': ['forum:read', 'forum:post'],
            'expires_at': '2026-05-11T13:00:00.000Z',
            'status': 'pending',
          }),
          200,
        );
      }),
    );

    final challenge = await client.fetchChallenge('wsc_abc');

    expect(challenge.challengeId, 'wsc_abc');
    expect(challenge.scopes, ['forum:read', 'forum:post']);
    expect(challenge.isExpired(DateTime.utc(2026, 5, 11, 12, 59)), isFalse);
  });

  test('approve posts the signed grant payload', () async {
    final grant = WebSessionGrant(
      challengeId: 'wsc_abc',
      relayOrigin: 'https://relay.trisaura.io',
      webOrigin: 'https://trisaura.io',
      subjectDid: 'did:plc:abc23456789',
      approvingDeviceId: 'app_device_abc',
      scopes: const ['forum:post'],
      expiresAt: DateTime.utc(2026, 5, 11, 13),
      createdAt: DateTime.utc(2026, 5, 11, 12, 45),
    );
    final client = WebSessionApprovalClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/web-sessions/approve');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['challenge_id'], 'wsc_abc');
        expect(body['subject_did'], 'did:plc:abc23456789');
        expect(body['signature'], 'sig-hex');
        expect(body['grant']['web_origin'], 'https://trisaura.io');
        expect(body['grant']['approving_device_id'], 'app_device_abc');
        return http.Response(
          jsonEncode({
            'session_token': 'wst_token',
            'trust_tier': 'self_custody_did',
            'expires_at': '2026-05-11T13:00:00.000Z',
          }),
          200,
        );
      }),
    );

    final result = await client.approve(
      SignedWebSessionGrant(grant: grant, signatureHex: 'sig-hex'),
    );

    expect(result.sessionToken, 'wst_token');
    expect(result.trustTier, 'self_custody_did');
  });

  test('reject posts the challenge id', () async {
    final client = WebSessionApprovalClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/web-sessions/reject');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['challenge_id'], 'wsc_abc');
        return http.Response('{}', 200);
      }),
    );

    await client.reject('wsc_abc');
  });

  test('fetchSessions reads active web sessions with bearer token', () async {
    final client = WebSessionApprovalClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/web-sessions');
        expect(request.headers['authorization'], 'Bearer wst_current');
        return http.Response(
          jsonEncode({
            'sessions': [
              {
                'session_id': 'wsi_current',
                'subject_did': 'did:plc:abc23456789',
                'approving_device_id': 'app_device_abc',
                'web_origin': 'https://trisaura.io',
                'relay_origin': 'https://relay.trisaura.io',
                'trust_tier': 'self_custody_did',
                'scopes': ['forum:read'],
                'created_at': '2026-05-11T12:00:00.000Z',
                'expires_at': '2026-05-11T13:00:00.000Z',
              },
            ],
          }),
          200,
        );
      }),
    );

    final sessions = await client.fetchSessions('wst_current');

    expect(sessions.single.sessionId, 'wsi_current');
    expect(sessions.single.sessionToken, isNull);
    expect(sessions.single.trustTier, 'self_custody_did');
  });

  test('revokeSession posts bearer and target session id', () async {
    final client = WebSessionApprovalClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/web-sessions/revoke');
        expect(request.headers['authorization'], 'Bearer wst_current');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['session_id'], 'wsi_other');
        return http.Response(jsonEncode({'revoked': true}), 200);
      }),
    );

    await client.revokeSession(
      bearerToken: 'wst_current',
      sessionId: 'wsi_other',
    );
  });

  test('relay errors are exposed as typed exceptions', () async {
    final client = WebSessionApprovalClient(
      baseUrl: 'http://relay.local',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({'error': 'expired_challenge', 'message': 'expired'}),
          401,
        );
      }),
    );

    await expectLater(
      client.fetchChallenge('wsc_abc'),
      throwsA(
        isA<WebSessionApprovalException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.error, 'error', 'expired_challenge'),
      ),
    );
  });
}
