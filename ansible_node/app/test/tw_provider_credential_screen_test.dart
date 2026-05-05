import 'package:ansible_node/screens/tw_provider_credential_screen.dart';
import 'package:ansible_node/services/external_url_launcher.dart';
import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      isNotNull,
    );
    expect(find.text('憑證已加入 Wallet'), findsOneWidget);
  });
}

class FakeTwIssuerClient extends VcIssuerClient {
  FakeTwIssuerClient({
    required this.offer,
    this.statuses = const [],
    Map<String, dynamic>? vc,
  }) : vc = vc ?? humanityVcFixture(),
       super(baseUrl: 'http://issuer.test');

  final TwProviderOffer offer;
  final List<String> statuses;
  final Map<String, dynamic> vc;
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
    return vc;
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

Map<String, dynamic> humanityVcFixture() {
  return {
    '@context': ['https://www.w3.org/ns/credentials/v2'],
    'id': 'urn:uuid:tw-provider-humanity',
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
