import 'package:ansible_node/screens/tw_provider_credential_screen.dart';
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

  testWidgets('panel starts TW provider flow and launches authorization URL', (
    tester,
  ) async {
    final client = FakeTwIssuerClient(offer: twOfferFixture());
    final launcher = FakeExternalUrlLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TwProviderCredentialPanel(
            holderDid: 'did:plc:abcdefghijklmnop',
            vcIssuerClient: client,
            urlLauncher: launcher,
            walletRepository: InMemoryWalletRepository(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.tap(find.text('開始驗證'));
    await tester.pump();

    expect(client.startedWithDid, 'did:plc:abcdefghijklmnop');
    expect(client.startedWithEmail, 'alice@example.com');
    expect(launcher.opened.single.toString(), contains('state-1'));
    expect(find.text('等待 provider 驗證完成'), findsOneWidget);
  });

  testWidgets('starts TW provider flow and launches authorization URL', (
    tester,
  ) async {
    final client = FakeTwIssuerClient(
      offer: TwProviderOffer(
        offerId: 'offer-1',
        state: 'state-1',
        authorizationUrl: Uri.parse(
          'https://provider.example/authorize?state=state-1',
        ),
        expiresAt: DateTime.utc(2026, 5, 5, 12, 5),
      ),
    );
    final launcher = FakeExternalUrlLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: TwProviderCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: launcher,
          walletRepository: InMemoryWalletRepository(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.tap(find.text('開始驗證'));
    await tester.pump();

    expect(client.startedWithDid, 'did:plc:abcdefghijklmnop');
    expect(client.startedWithEmail, 'alice@example.com');
    expect(launcher.opened.single.toString(), contains('state-1'));
    expect(find.text('等待 provider 驗證完成'), findsOneWidget);
  });

  testWidgets('polls until verified then issues and stores credential', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository();
    final client = FakeTwIssuerClient(
      offer: twOfferFixture(),
      statuses: ['pending', 'verified'],
      vc: humanityVcFixture(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TwProviderCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: client,
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: repo,
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 1),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.tap(find.text('開始驗證'));
    await tester.pump(const Duration(milliseconds: 50));

    final credentials = await repo.listCredentials();
    expect(credentials.single.credentialType, 'TrisAuraHumanityCredential');
    expect(credentials.single.holderDid, 'did:plc:abcdefghijklmnop');
    expect(
      await repo.getEncryptedPayload(credentials.single.credentialId),
      startsWith('secure-storage-json-v1:'),
    );
    expect(find.text('憑證已加入 Wallet'), findsOneWidget);
  });

  testWidgets('launch failure keeps offer and shows retry actions', (
    tester,
  ) async {
    final launcher = FakeExternalUrlLauncher(shouldOpen: false);
    await tester.pumpWidget(
      MaterialApp(
        home: TwProviderCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: FakeTwIssuerClient(offer: twOfferFixture()),
          urlLauncher: launcher,
          walletRepository: InMemoryWalletRepository(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.tap(find.text('開始驗證'));
    await tester.pump();

    expect(find.text('開啟驗證頁失敗'), findsOneWidget);
    expect(find.text('重新開啟驗證頁'), findsOneWidget);
    expect(find.text('重新檢查'), findsOneWidget);
  });

  testWidgets('poll timeout shows check again and start over actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TwProviderCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: FakeTwIssuerClient(
            offer: twOfferFixture(),
            statuses: ['pending', 'pending', 'pending'],
          ),
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: InMemoryWalletRepository(),
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(milliseconds: 20),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.tap(find.text('開始驗證'));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('尚未收到驗證結果'), findsOneWidget);
    expect(find.text('重新檢查'), findsOneWidget);
    expect(find.text('重新開始'), findsOneWidget);
  });

  testWidgets('provider_not_verified keeps waiting state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TwProviderCredentialScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          vcIssuerClient: FakeTwIssuerClient(
            offer: twOfferFixture(),
            statuses: ['verified'],
            issueError: const VcIssuerException(
              statusCode: 409,
              error: 'provider_not_verified',
            ),
          ),
          urlLauncher: FakeExternalUrlLauncher(),
          walletRepository: InMemoryWalletRepository(),
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 1),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.tap(find.text('開始驗證'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('等待 provider 驗證完成'), findsOneWidget);
  });

  testWidgets(
    'security errors require restart without echoing sensitive fields',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TwProviderCredentialScreen(
            holderDid: 'did:plc:abcdefghijklmnop',
            vcIssuerClient: FakeTwIssuerClient(
              offer: twOfferFixture(),
              statuses: ['verified'],
              issueError: const VcIssuerException(
                statusCode: 401,
                error: 'invalid_provider_proof',
              ),
            ),
            urlLauncher: FakeExternalUrlLauncher(),
            walletRepository: InMemoryWalletRepository(),
            pollInterval: const Duration(milliseconds: 10),
            pollTimeout: const Duration(seconds: 1),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.tap(find.text('開始驗證'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('驗證安全檢查失敗，請重新開始。'), findsOneWidget);
      expect(find.text('重新開始'), findsOneWidget);
      expect(find.textContaining('SIGNED_ASSERTION_PAYLOAD'), findsNothing);
    },
  );
}

class FakeTwIssuerClient extends VcIssuerClient {
  FakeTwIssuerClient({
    required this.offer,
    this.statuses = const [],
    Map<String, dynamic>? vc,
    this.issueError,
  }) : vc = vc ?? humanityVcFixture(),
       super(baseUrl: 'http://issuer.test');

  final TwProviderOffer offer;
  final List<String> statuses;
  final Map<String, dynamic> vc;
  final Object? issueError;
  String? startedWithDid;
  String? startedWithEmail;
  var _statusIndex = 0;

  @override
  Future<TwProviderOffer> startTwProviderFlow({
    required String did,
    required String email,
  }) async {
    startedWithDid = did;
    startedWithEmail = email;
    return offer;
  }

  @override
  Future<TwProviderStatus> getTwProviderStatus(String offerId) async {
    final index = _statusIndex;
    if (_statusIndex < statuses.length - 1) {
      _statusIndex += 1;
    }
    return TwProviderStatus(
      status: statuses.isEmpty ? 'pending' : statuses[index],
    );
  }

  @override
  Future<Map<String, dynamic>> issueTwProviderCredential({
    required String did,
    required String email,
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

TwProviderOffer twOfferFixture() {
  return TwProviderOffer(
    offerId: 'offer-1',
    state: 'state-1',
    authorizationUrl: Uri.parse(
      'https://provider.example/authorize?state=state-1',
    ),
    expiresAt: DateTime.utc(2026, 5, 5, 12, 5),
  );
}

Map<String, dynamic> humanityVcFixture() {
  return {
    '@context': [
      'https://www.w3.org/ns/credentials/v2',
      'https://elix.cool/contexts/humanity/v1',
    ],
    'id': 'urn:uuid:tw-provider-humanity',
    'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
    'issuer': 'did:web:issuer.elix.cool',
    'validFrom': '2026-05-05T12:00:00Z',
    'validUntil': '2026-08-03T12:00:00Z',
    'credentialSubject': {
      'id': 'did:plc:abcdefghijklmnop',
      'humanVerified': true,
      'assuranceMethod': 'tw_fido_or_moica',
    },
    'proof': {
      '@context': [
        'https://www.w3.org/ns/credentials/v2',
        'https://elix.cool/contexts/humanity/v1',
      ],
      'type': 'DataIntegrityProof',
      'cryptosuite': 'eddsa-jcs-2022',
      'created': '2026-05-05T12:00:00Z',
      'verificationMethod': 'did:web:issuer.elix.cool#key-1',
      'proofPurpose': 'assertionMethod',
      'proofValue': 'zabcd',
    },
  };
}
