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
}

class FakeTwIssuerClient extends VcIssuerClient {
  FakeTwIssuerClient({required this.offer})
    : super(baseUrl: 'http://issuer.test');

  final TwProviderOffer offer;
  String? startedWithDid;
  String? startedWithEmail;

  @override
  Future<TwProviderOffer> startTwProviderFlow({
    required String did,
    required String email,
  }) async {
    startedWithDid = did;
    startedWithEmail = email;
    return offer;
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
