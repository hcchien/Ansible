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
          client: _FakeApprovalClient(audience: 'https://forum.elix.cool'),
          grantService: _FakeGrantService(),
          deviceIdProvider: const _FakeDeviceIdProvider(),
          now: () => DateTime.utc(2026, 5, 11, 12, 50),
        ),
      ),
    );
    await tester.pump();

    // Without localization delegates the app copy falls back to zh-Hant.
    expect(find.text('核准網頁工作階段'), findsOneWidget);
    expect(find.text('https://elix.cool'), findsOneWidget);
    expect(find.text('https://relay.elix.cool'), findsOneWidget);
    expect(find.text('Forum Host'), findsOneWidget);
    expect(find.text('https://forum.elix.cool'), findsOneWidget);
    expect(find.text('forum:read'), findsOneWidget);
    expect(find.text('forum:post'), findsOneWidget);
    expect(find.text('did:plc:abc23456789'), findsOneWidget);
    expect(find.text('請求有效期限'), findsOneWidget);
    expect(find.text('工作階段有效期限'), findsOneWidget);
    expect(
      find.text(DateTime.utc(2026, 5, 12, 0, 50).toLocal().toIso8601String()),
      findsOneWidget,
    );
  });

  testWidgets('approves only after user taps approve', (tester) async {
    final client = _FakeApprovalClient(audience: 'https://forum.elix.cool');
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

    await tester.ensureVisible(find.text('核准'));
    await tester.pump();
    await tester.tap(find.text('核准'));
    await tester.pumpAndSettle();

    expect(client.approveCalled, isTrue);
    expect(grantService.signedGrant?.subjectDid, 'did:plc:abc23456789');
    expect(grantService.signedGrant?.approvingDeviceId, 'app_device_test');
    expect(grantService.signedGrant?.audience, 'https://forum.elix.cool');
    expect(
      grantService.signedGrant?.expiresAt,
      DateTime.utc(2026, 5, 12, 0, 50),
    );
    expect(approved?.sessionToken, 'wst_token');
  });

  testWidgets('closes with approved result after user approves', (
    tester,
  ) async {
    bool? routeResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: const Text('Settings page'),
            floatingActionButton: ElevatedButton(
              key: const Key('open_web_session_approval'),
              onPressed: () async {
                routeResult = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => WebSessionApprovalScreen(
                      challengeId: 'wsc_abc',
                      currentDid: 'did:plc:abc23456789',
                      client: _FakeApprovalClient(),
                      grantService: _FakeGrantService(),
                      deviceIdProvider: const _FakeDeviceIdProvider(),
                      now: () => DateTime.utc(2026, 5, 11, 12, 50),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_web_session_approval')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('核准'));
    await tester.pump();
    await tester.tap(find.text('核准'));
    await tester.pumpAndSettle();

    expect(routeResult, isTrue);
    expect(find.text('Settings page'), findsOneWidget);
    expect(find.text('核准網頁工作階段'), findsNothing);
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

    await tester.tap(find.text('拒絕'));
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
      find.widgetWithText(ElevatedButton, '核准'),
    );
    expect(approve.onPressed, isNull);
    expect(find.text('此請求已過期。'), findsOneWidget);
  });
}

class _FakeApprovalClient implements WebSessionApprovalGateway {
  bool approveCalled = false;
  String? rejectedChallengeId;
  final DateTime expiresAt;
  final String? audience;

  _FakeApprovalClient({DateTime? expiresAt, this.audience})
    : expiresAt = expiresAt ?? DateTime.utc(2026, 5, 11, 13);

  @override
  Future<WebSessionChallenge> fetchChallenge(String challengeId) async {
    return WebSessionChallenge(
      challengeId: challengeId,
      relayOrigin: 'https://relay.elix.cool',
      webOrigin: 'https://elix.cool',
      audience: audience,
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
