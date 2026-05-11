import 'package:ansible_node/screens/web_session_management_screen.dart';
import 'package:ansible_node/services/web_session_approval_client.dart';
import 'package:ansible_node/services/web_session_grant_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists and revokes web sessions', (tester) async {
    final client = _FakeSessionClient();

    await tester.pumpWidget(
      MaterialApp(
        home: WebSessionManagementScreen(
          bearerToken: 'wst_current',
          client: client,
          now: () => DateTime.utc(2026, 5, 11, 12, 30),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Web sessions'), findsOneWidget);
    expect(find.text('https://trisaura.io'), findsOneWidget);
    expect(find.textContaining('app_device_abc'), findsOneWidget);

    await tester.tap(find.text('Revoke').first);
    await tester.pumpAndSettle();

    expect(client.revokedToken, 'wst_other');
    expect(find.textContaining('wst_other'), findsNothing);
  });
}

class _FakeSessionClient implements WebSessionApprovalGateway {
  String? revokedToken;
  final List<WebSessionRecord> sessions = [
    WebSessionRecord(
      sessionToken: 'wst_other',
      subjectDid: 'did:plc:abc23456789',
      approvingDeviceId: 'app_device_abc',
      webOrigin: 'https://trisaura.io',
      relayOrigin: 'https://relay.trisaura.io',
      trustTier: 'self_custody_did',
      scopes: const ['forum:read', 'forum:post'],
      createdAt: DateTime.utc(2026, 5, 11, 12),
      expiresAt: DateTime.utc(2026, 5, 11, 13),
    ),
  ];

  @override
  Future<WebSessionChallenge> fetchChallenge(String challengeId) async {
    throw UnimplementedError();
  }

  @override
  Future<WebSessionApprovalResult> approve(
    SignedWebSessionGrant signedGrant,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> reject(String challengeId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<WebSessionRecord>> fetchSessions(String bearerToken) async {
    return List.unmodifiable(sessions);
  }

  @override
  Future<void> revokeSession({
    required String bearerToken,
    required String sessionToken,
  }) async {
    revokedToken = sessionToken;
    sessions.removeWhere((session) => session.sessionToken == sessionToken);
  }
}
