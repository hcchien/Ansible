import 'package:ansible_node/screens/credential_issuance_wizard.dart';
import 'package:ansible_node/screens/wallet_screen.dart';
import 'package:ansible_node/services/external_url_launcher.dart';
import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wallet screen lists credential status and expiry', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository.withCredentials([
      WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.trisaura.io',
        holderDid: 'did:key:z6Mkholder',
        credentialType: 'TrisAuraHumanityCredential',
        status: WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 4),
        validUntil: DateTime.utc(2026, 8, 2),
        displayName: 'Verified Human',
        createdAt: DateTime.utc(2026, 5, 4, 10),
        updatedAt: DateTime.utc(2026, 5, 4, 10),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WALLET'), findsOneWidget);
    expect(find.text('錢包'), findsOneWidget);
    await _scrollWallet(tester);
    expect(find.text('Verified Human'), findsOneWidget);
    expect(find.text('有效'), findsOneWidget);
    expect(find.text('到期 2026-08-02'), findsOneWidget);
  });

  testWidgets('wallet screen shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: InMemoryWalletRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollWallet(tester);
    expect(find.text('還沒有憑證'), findsOneWidget);
    expect(find.text('新增憑證'), findsWidgets);
  });

  testWidgets('wallet screen does not render hard-coded identity mocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: InMemoryWalletRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('公開 · Tris'), findsNothing);
    expect(find.text('讀書會 · Tris'), findsNothing);
    expect(find.text('匿名瀏覽'), findsNothing);
    expect(find.textContaining('8c4d'), findsNothing);
    expect(find.textContaining('c91a'), findsNothing);
    expect(find.text('本人'), findsOneWidget);
  });

  testWidgets('empty wallet add credential expands inline wizard', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollWallet(tester);
    await tester.tap(find.text('新增憑證').first);
    await tester.pumpAndSettle();

    expect(find.byType(CredentialIssuanceWizard), findsOneWidget);
    expect(find.text('TW 身份驗證'), findsOneWidget);
    expect(find.text('Email OTP / Legacy'), findsOneWidget);
  });

  testWidgets('wallet identity add credential expands inline wizard', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository.withCredentials([
      WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.trisaura.io',
        holderDid: 'did:plc:abcdefghijklmnop',
        credentialType: 'TrisAuraHumanityCredential',
        status: WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 5),
        validUntil: DateTime.utc(2026, 8, 3),
        displayName: 'Verified Human',
        createdAt: DateTime.utc(2026, 5, 5),
        updatedAt: DateTime.utc(2026, 5, 5),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollWallet(tester);
    await tester.tap(find.text('新增憑證').first);
    await tester.pumpAndSettle();

    expect(find.byType(CredentialIssuanceWizard), findsOneWidget);
    expect(find.text('TW 身份驗證'), findsOneWidget);
  });

  testWidgets('successful inline TW issuance reloads wallet and hides wizard', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: repo,
          vcIssuerClient: FakeTwIssuerClient(
            offer: twOfferFixture(),
            statuses: ['verified'],
          ),
          urlLauncher: FakeExternalUrlLauncher(),
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollWallet(tester);
    await tester.tap(find.text('新增憑證').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TW 身份驗證'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'alice@example.com');
    await tester.ensureVisible(find.text('開始驗證'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始驗證'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(CredentialIssuanceWizard), findsNothing);
    await _scrollWallet(tester);
    expect(find.text('Verified Human'), findsOneWidget);
  });
}

Future<void> _scrollWallet(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -520));
  await tester.pumpAndSettle();
}

class FakeTwIssuerClient extends VcIssuerClient {
  FakeTwIssuerClient({required this.offer, this.statuses = const []})
    : super(baseUrl: 'http://issuer.test');

  final TwProviderOffer offer;
  final List<String> statuses;
  var _statusIndex = 0;

  @override
  Future<TwProviderOffer> startTwProviderFlow({
    required String did,
    required String email,
  }) async {
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
    return {
      '@context': ['https://www.w3.org/ns/credentials/v2'],
      'id': 'urn:uuid:inline-humanity',
      'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
      'issuer': 'did:web:issuer.trisaura.io',
      'issuanceDate': '2026-05-05T12:00:00Z',
      'expirationDate': '2026-08-03T12:00:00Z',
      'credentialSubject': {'id': 'did:plc:abcdefghijklmnop', 'humanity': true},
      'proof': {
        'type': 'Ed25519Signature2020',
        'created': '2026-05-05T12:00:00Z',
        'verificationMethod': 'did:web:issuer.trisaura.io#key-1',
        'proofPurpose': 'assertionMethod',
        'proofValue': 'abcd',
      },
    };
  }
}

class FakeExternalUrlLauncher implements ExternalUrlLauncher {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
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
