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

    expect(find.text('網頁工作階段'), findsOneWidget);
    expect(find.text('https://elix.cool'), findsOneWidget);
    expect(find.textContaining('app_device_abc'), findsOneWidget);

    await tester.tap(find.text('撤銷').first);
    await tester.pumpAndSettle();

    expect(client.revokedSessionId, 'wsi_other');
    expect(find.textContaining('wsi_other'), findsNothing);
    expect(find.textContaining('wst_other'), findsNothing);
  });
}

class _FakeSessionClient implements WebSessionApprovalGateway {
  String? revokedSessionId;
  final List<WebSessionRecord> sessions = [
    WebSessionRecord(
      sessionId: 'wsi_other',
      sessionToken: 'wst_other',
      subjectDid: 'did:plc:abc23456789',
      approvingDeviceId: 'app_device_abc',
      webOrigin: 'https://elix.cool',
      relayOrigin: 'https://relay.elix.cool',
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
    String? sessionId,
    String? sessionToken,
  }) async {
    revokedSessionId = sessionId;
    sessions.removeWhere((session) => session.sessionId == sessionId);
  }
}
