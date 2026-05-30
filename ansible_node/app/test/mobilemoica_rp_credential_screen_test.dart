import 'package:ansible_node/screens/mobilemoica_rp_credential_screen.dart';
import 'package:ansible_node/services/external_url_launcher.dart';
import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'uses MobileMoica result polling interval recommended by the interface spec',
    () {
      const screen = MobileMoicaRPCredentialScreen(
        holderDid: 'did:plc:abcdefghijklmnop',
      );
      const panel = MobileMoicaRPCredentialPanel(
        holderDid: 'did:plc:abcdefghijklmnop',
      );

      expect(screen.pollInterval, const Duration(seconds: 4));
      expect(panel.pollInterval, const Duration(seconds: 4));
    },
  );

  testWidgets('shows disclosure before national ID entry', (tester) async {
    final client = FakeMobileMoicaIssuerClient();

    await tester.pumpWidget(
      MaterialApp(
        home: MobileMoicaRPCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: InMemoryWalletRepository(),
        ),
      ),
    );

    expect(find.textContaining('不是 zkID'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobilemoica-national-id-field')),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mobilemoica-start-button')),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('accepted flow posts national ID and opens MobileMoica', (
    tester,
  ) async {
    final client = FakeMobileMoicaIssuerClient();
    final launcher = FakeExternalUrlLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: MobileMoicaRPCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: launcher,
          walletRepository: InMemoryWalletRepository(),
        ),
      ),
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobilemoica-national-id-field')),
      'Z123000000',
    );
    await tester.pump();
    await tester.tap(find.text('開啟 TW FidO'));
    await tester.pump();

    expect(client.startedWithDid, 'did:plc:abcdefghijklmnop');
    expect(client.startedWithNationalId, 'Z123000000');
    expect(client.startedWithConsentVersion, 'mobilemoica-rp-v1');
    expect(client.startedWithConsentCopyHash, startsWith('sha256:'));
    expect(launcher.opened.single.scheme, 'mobilemoica');
    expect(find.text('等待 TW FidO 驗證完成'), findsOneWidget);
  });

  testWidgets('polls until verified then issues and stores credential', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository();
    final client = FakeMobileMoicaIssuerClient(
      statuses: ['pending', 'verified'],
      vc: mobileMoicaVcFixture(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MobileMoicaRPCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: repo,
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 1),
        ),
      ),
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobilemoica-national-id-field')),
      'Z123000000',
    );
    await tester.pump();
    await tester.tap(find.text('開啟 TW FidO'));
    await tester.pump(const Duration(milliseconds: 50));

    final credentials = await repo.listCredentials();
    expect(credentials.single.credentialType, 'TrisAuraHumanityCredential');
    expect(credentials.single.displayName, 'MobileMoica Verified Human');
    expect(find.text('憑證已加入 Wallet'), findsOneWidget);
  });

  testWidgets('stops polling while the app is not foregrounded', (
    tester,
  ) async {
    final client = FakeMobileMoicaIssuerClient(statuses: ['pending']);

    await tester.pumpWidget(
      MaterialApp(
        home: MobileMoicaRPCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: InMemoryWalletRepository(),
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 1),
        ),
      ),
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobilemoica-national-id-field')),
      'Z123000000',
    );
    await tester.pump();
    await tester.tap(find.text('開啟 TW FidO'));
    await tester.pump();

    expect(client.statusCallCount, greaterThan(0));
    final callsBeforePause = client.statusCallCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.statusCallCount, callsBeforePause);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 20));

    expect(client.statusCallCount, greaterThan(callsBeforePause));
  });

  testWidgets('security errors do not echo sensitive fields', (tester) async {
    final client = FakeMobileMoicaIssuerClient(
      statuses: ['verified'],
      issueError: const VcIssuerException(
        statusCode: 401,
        error: 'invalid_provider_proof:Z123000000:SIGNED_RESPONSE',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MobileMoicaRPCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: InMemoryWalletRepository(),
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 1),
        ),
      ),
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobilemoica-national-id-field')),
      'Z123000000',
    );
    await tester.pump();
    await tester.tap(find.text('開啟 TW FidO'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('驗證安全檢查失敗，請重新開始。'), findsOneWidget);
    expect(find.textContaining('Z123000000'), findsNothing);
    expect(find.textContaining('SIGNED_RESPONSE'), findsNothing);
  });
}

class FakeMobileMoicaIssuerClient extends VcIssuerClient {
  FakeMobileMoicaIssuerClient({
    this.statuses = const [],
    Map<String, dynamic>? vc,
    this.issueError,
  }) : vc = vc ?? mobileMoicaVcFixture(),
       super(baseUrl: 'http://issuer.test');

  final List<String> statuses;
  final Map<String, dynamic> vc;
  final Object? issueError;
  String? startedWithDid;
  String? startedWithNationalId;
  String? startedWithConsentVersion;
  String? startedWithConsentCopyHash;
  int statusCallCount = 0;
  var _statusIndex = 0;

  @override
  Future<MobileMoicaRPOffer> startMobileMoicaRPFlow({
    required String holderDid,
    required String nationalId,
    required String consentVersion,
    required String consentCopyHash,
    required String locale,
  }) async {
    startedWithDid = holderDid;
    startedWithNationalId = nationalId;
    startedWithConsentVersion = consentVersion;
    startedWithConsentCopyHash = consentCopyHash;
    return MobileMoicaRPOffer(
      offerId: 'offer-1',
      deepLinkUrl: Uri.parse(
        'mobilemoica://moica.moi.gov.tw/a2a/verifySign?sp_ticket=contract',
      ),
      expiresAt: DateTime.utc(2026, 5, 30, 12, 5),
    );
  }

  @override
  Future<MobileMoicaRPStatus> getMobileMoicaRPStatus(String offerId) async {
    statusCallCount += 1;
    final index = _statusIndex;
    if (_statusIndex < statuses.length - 1) {
      _statusIndex += 1;
    }
    return MobileMoicaRPStatus(
      status: statuses.isEmpty ? 'pending' : statuses[index],
    );
  }

  @override
  Future<Map<String, dynamic>> issueMobileMoicaRPCredential({
    required String holderDid,
    required String offerId,
  }) async {
    final error = issueError;
    if (error != null) throw error;
    return vc;
  }
}

class FakeExternalUrlLauncher implements ExternalUrlLauncher {
  FakeExternalUrlLauncher({this.shouldOpen = true});

  final bool shouldOpen;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return shouldOpen;
  }
}

Map<String, dynamic> mobileMoicaVcFixture() {
  return {
    '@context': [
      'https://www.w3.org/ns/credentials/v2',
      'https://trisaura.io/contexts/humanity/v1',
    ],
    'id': 'urn:uuid:mobilemoica-humanity',
    'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
    'issuer': 'did:web:issuer.trisaura.io',
    'validFrom': '2026-05-30T12:00:00Z',
    'validUntil': '2026-08-28T12:00:00Z',
    'credentialSubject': {
      'id': 'did:plc:abcdefghijklmnop',
      'humanVerified': true,
      'assuranceLevel': 'tw_natural_person_certificate',
      'assuranceMethod': 'mobilemoica_rp_explicit_disclosure',
      'jurisdiction': 'TW',
      'disclosureModel': 'explicit_rp',
    },
    'proof': {
      'type': 'Ed25519Signature2020',
      'created': '2026-05-30T12:00:00Z',
      'verificationMethod': 'did:web:issuer.trisaura.io#key-1',
      'proofPurpose': 'assertionMethod',
      'proofValue': 'abcd',
    },
  };
}
