import 'package:ansible_node/screens/web_session_approval_screen.dart';
import 'package:ansible_node/services/web_session_approval_client.dart';
import 'package:ansible_node/services/web_session_grant_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows web session challenge details before approval', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WebSessionApprovalScreen(
          challengeId: 'wsc_abc',
          currentDid: 'did:plc:abc23456789',
          client: _FakeApprovalClient(),
          grantService: _FakeGrantService(),
          deviceIdProvider: const _FakeDeviceIdProvider(),
          now: () => DateTime.utc(2026, 5, 11, 12, 50),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Approve web session'), findsOneWidget);
    expect(find.text('https://trisaura.io'), findsOneWidget);
    expect(find.text('https://relay.trisaura.io'), findsOneWidget);
    expect(find.text('forum:read'), findsOneWidget);
    expect(find.text('forum:post'), findsOneWidget);
    expect(find.text('did:plc:abc23456789'), findsOneWidget);
    expect(find.text('Request expires'), findsOneWidget);
    expect(find.text('Session expires'), findsOneWidget);
    expect(
      find.text(DateTime.utc(2026, 5, 12, 0, 50).toLocal().toIso8601String()),
      findsOneWidget,
    );
  });

  testWidgets('approves only after user taps approve', (tester) async {
    final client = _FakeApprovalClient();
    final grantService = _FakeGrantService();
    WebSessionApprovalResult? approved;

    await tester.pumpWidget(
      MaterialApp(
        home: WebSessionApprovalScreen(
          challengeId: 'wsc_abc',
          currentDid: 'did:plc:abc23456789',
          client: client,
          grantService: grantService,
          deviceIdProvider: const _FakeDeviceIdProvider(),
          now: () => DateTime.utc(2026, 5, 11, 12, 50),
          onApproved: (result) => approved = result,
        ),
      ),
    );
    await tester.pump();

    expect(client.approveCalled, isFalse);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(client.approveCalled, isTrue);
    expect(grantService.signedGrant?.subjectDid, 'did:plc:abc23456789');
    expect(grantService.signedGrant?.approvingDeviceId, 'app_device_test');
    expect(
      grantService.signedGrant?.expiresAt,
      DateTime.utc(2026, 5, 12, 0, 50),
    );
    expect(approved?.sessionToken, 'wst_token');
  });

  testWidgets('rejects when user taps reject', (tester) async {
    final client = _FakeApprovalClient();
    var rejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WebSessionApprovalScreen(
          challengeId: 'wsc_abc',
          currentDid: 'did:plc:abc23456789',
          client: client,
          grantService: _FakeGrantService(),
          deviceIdProvider: const _FakeDeviceIdProvider(),
          now: () => DateTime.utc(2026, 5, 11, 12, 50),
          onRejected: () => rejected = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(client.rejectedChallengeId, 'wsc_abc');
    expect(rejected, isTrue);
  });

  testWidgets('disables approval for expired challenges', (tester) async {
    final client = _FakeApprovalClient(
      expiresAt: DateTime.utc(2026, 5, 11, 12, 40),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WebSessionApprovalScreen(
          challengeId: 'wsc_abc',
          currentDid: 'did:plc:abc23456789',
          client: client,
          grantService: _FakeGrantService(),
          deviceIdProvider: const _FakeDeviceIdProvider(),
          now: () => DateTime.utc(2026, 5, 11, 12, 50),
        ),
      ),
    );
    await tester.pump();

    final approve = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Approve'),
    );
    expect(approve.onPressed, isNull);
    expect(find.text('This request has expired.'), findsOneWidget);
  });
}

class _FakeApprovalClient implements WebSessionApprovalGateway {
  bool approveCalled = false;
  String? rejectedChallengeId;
  final DateTime expiresAt;

  _FakeApprovalClient({DateTime? expiresAt})
    : expiresAt = expiresAt ?? DateTime.utc(2026, 5, 11, 13);

  @override
  Future<WebSessionChallenge> fetchChallenge(String challengeId) async {
    return WebSessionChallenge(
      challengeId: challengeId,
      relayOrigin: 'https://relay.trisaura.io',
      webOrigin: 'https://trisaura.io',
      scopes: const ['forum:read', 'forum:post'],
      expiresAt: expiresAt,
      status: 'pending',
    );
  }

  @override
  Future<WebSessionApprovalResult> approve(
    SignedWebSessionGrant signedGrant,
  ) async {
    approveCalled = true;
    return WebSessionApprovalResult(
      sessionToken: 'wst_token',
      trustTier: 'self_custody_did',
      expiresAt: DateTime.utc(2026, 5, 11, 13),
    );
  }

  @override
  Future<void> reject(String challengeId) async {
    rejectedChallengeId = challengeId;
  }

  @override
  Future<List<WebSessionRecord>> fetchSessions(String bearerToken) async {
    return const [];
  }

  @override
  Future<void> revokeSession({
    required String bearerToken,
    String? sessionId,
    String? sessionToken,
  }) async {}
}

class _FakeGrantService implements WebSessionGrantSigner {
  WebSessionGrant? signedGrant;

  @override
  Future<SignedWebSessionGrant> sign(WebSessionGrant grant) async {
    signedGrant = grant;
    return SignedWebSessionGrant(grant: grant, signatureHex: 'sig-hex');
  }
}

class _FakeDeviceIdProvider implements WebSessionDeviceIdProvider {
  const _FakeDeviceIdProvider();

  @override
  Future<String> getOrCreateDeviceId() async => 'app_device_test';
}
