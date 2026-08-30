import 'package:ansible_node/screens/credential_issuance_wizard.dart';
import 'package:ansible_node/screens/credential_detail_screen.dart';
import 'package:ansible_node/screens/wallet_screen.dart';
import 'package:ansible_node/services/external_url_launcher.dart';
import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:ansible_node/services/public_profile_credential_preferences.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('wallet keeps Paper button contrast in system dark mode', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.theme(),
        darkTheme: AnsibleDesign.darkTheme(),
        themeMode: ThemeMode.dark,
        home: WalletScreen(holderDid: 'did:elix:test', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    final label = find.text('新增憑證');
    expect(
      DefaultTextStyle.of(tester.element(label)).style.color,
      AnsibleDesign.ink,
    );
  });

  testWidgets('wallet screen lists credential status and expiry', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository.withCredentials([
      WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.elix.cool',
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

    expect(find.text('皮夾'), findsWidgets);
    await _scrollWallet(tester);
    expect(find.text('真人驗證'), findsOneWidget);
    expect(find.text('有效'), findsOneWidget);
    expect(find.text('到期 2026-08-02'), findsOneWidget);
  });

  testWidgets(
    'each eligible VC can be selected for the public profile without authentication',
    (tester) async {
      final now = DateTime.utc(2026, 8, 27);
      final credential = WalletCredential(
        credentialId: 'urn:uuid:age-profile',
        issuerDid: 'did:web:issuer.elix.cool',
        holderDid: 'did:elix:profile-holder',
        credentialType: 'AgeOver18Credential',
        status: WalletCredentialStatus.active,
        validFrom: now,
        validUntil: DateTime.utc(2027, 8, 27),
        displayName: 'Age 18+',
        createdAt: now,
        updatedAt: now,
      );
      final preferences = MemoryPublicProfileCredentialPreferenceStore();

      await tester.pumpWidget(
        MaterialApp(
          home: WalletScreen(
            holderDid: credential.holderDid,
            repository: InMemoryWalletRepository.withCredentials([credential]),
            profileCredentialPreferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile_credential_urn:uuid:age-profile')),
        260,
      );

      await tester.tap(
        find.byKey(const ValueKey('profile_credential_urn:uuid:age-profile')),
      );
      await tester.pumpAndSettle();
      expect(find.text('放到個人檔案？'), findsOneWidget);
      expect(find.textContaining('完整憑證'), findsOneWidget);
      await tester.tap(find.text('繼續發布'));
      await tester.pumpAndSettle();

      expect(await preferences.selectedCredentialIds(credential.holderDid), {
        'urn:uuid:age-profile',
      });
      expect(find.text('已放到個人檔案'), findsOneWidget);
      // Authentication belongs to the single shared Sync ceremony; toggling a
      // Wallet preference never opens an authentication route or prompt.
      expect(find.textContaining('Face ID'), findsNothing);
    },
  );

  testWidgets('wallet lets the user copy the complete holder DID', (
    tester,
  ) async {
    const holderDid = 'did:elix:5smknabcdefghijklmnopqrstuhf';
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: holderDid,
          repository: InMemoryWalletRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('copy_holder_did')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a credential requires confirmation', (tester) async {
    final credential = WalletCredential(
      credentialId: 'urn:uuid:test-delete',
      issuerDid: 'did:web:issuer.elix.cool',
      holderDid: 'did:plc:abcdefghijklmnop',
      credentialType: 'TrisAuraHumanityCredential',
      status: WalletCredentialStatus.active,
      validFrom: DateTime.utc(2026, 5, 4),
      validUntil: DateTime.utc(2026, 8, 2),
      displayName: 'Verified Human',
      createdAt: DateTime.utc(2026, 5, 4, 10),
      updatedAt: DateTime.utc(2026, 5, 4, 10),
    );
    final repo = InMemoryWalletRepository.withCredentials([credential]);

    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(holderDid: credential.holderDid, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollWallet(tester);

    await tester.tap(
      find.byKey(const ValueKey('credential_actions_urn:uuid:test-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除本機憑證'));
    await tester.pumpAndSettle();
    expect(find.text('要刪除本機憑證嗎？'), findsOneWidget);
    expect(await repo.listCredentials(), hasLength(1));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await repo.listCredentials(), hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey('credential_actions_urn:uuid:test-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除本機憑證'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除憑證'));
    await tester.pumpAndSettle();
    expect(await repo.listCredentials(), isEmpty);
  });

  testWidgets('credential card opens local privacy-safe details', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository();
    final metadata = WalletCredential(
      credentialId: 'urn:uuid:test-citizenship',
      issuerDid: 'did:web:issuer-dev.elix.cool',
      holderDid: 'did:plc:abcdefghijklmnop',
      credentialType: 'TaiwanCitizenshipCredential',
      status: WalletCredentialStatus.active,
      validFrom: DateTime.utc(2026, 7, 24),
      validUntil: DateTime.utc(2026, 10, 22),
      displayName: 'Taiwan Citizenship',
      createdAt: DateTime.utc(2026, 7, 24),
      updatedAt: DateTime.utc(2026, 7, 24),
    );
    await repo.saveCredential(
      metadata: metadata,
      encryptedPayload: '''
{
  "id": "urn:uuid:test-citizenship",
  "type": ["VerifiableCredential", "TaiwanCitizenshipCredential"],
  "issuer": "did:web:issuer-dev.elix.cool",
  "validFrom": "2026-07-24T00:00:00Z",
  "validUntil": "2026-10-22T00:00:00Z",
  "credentialSubject": {
    "id": "did:plc:abcdefghijklmnop",
    "nationality": "TW"
  },
  "proof": {
    "type": "DataIntegrityProof",
    "cryptosuite": "eddsa-jcs-2022",
    "proofPurpose": "assertionMethod",
    "proofValue": "ztest"
  }
}
''',
      encryptionVersion: 'test-json',
    );

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

    await tester.tap(
      find.byKey(const Key('credential_urn:uuid:test-citizenship')),
    );
    await tester.pumpAndSettle();

    expect(find.text('憑證詳情'), findsOneWidget);
    expect(find.text('TaiwanCitizenshipCredential'), findsOneWidget);
    expect(find.text('TW'), findsOneWidget);
    expect(find.text('結構、期限與隱私欄位檢查通過'), findsOneWidget);
    expect(find.textContaining('Z123'), findsNothing);
    expect(find.textContaining('363027682'), findsNothing);
  });

  testWidgets(
    'credential detail keeps a safe summary when payload is missing',
    (tester) async {
      final repo = InMemoryWalletRepository();
      final metadata = WalletCredential(
        credentialId: 'urn:uuid:legacy-citizenship',
        issuerDid: 'did:web:issuer-dev.elix.cool',
        holderDid: 'did:plc:legacyholder',
        credentialType: 'TaiwanCitizenshipCredential',
        status: WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 7, 24),
        validUntil: DateTime.utc(2026, 10, 22),
        displayName: 'Taiwan Citizenship',
        createdAt: DateTime.utc(2026, 7, 24),
        updatedAt: DateTime.utc(2026, 7, 24),
      );
      await repo.saveCredential(
        metadata: metadata,
        encryptedPayload: 'secure-storage-json-v1:urn:uuid:legacy-citizenship',
        encryptionVersion: 'secure-storage-json-v1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WalletScreen(
            holderDid: 'did:plc:legacyholder',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollWallet(tester);
      await tester.tap(
        find.byKey(const Key('credential_urn:uuid:legacy-citizenship')),
      );
      await tester.pumpAndSettle();

      expect(find.text('僅能讀取憑證摘要'), findsOneWidget);
      expect(find.text('TaiwanCitizenshipCredential'), findsOneWidget);
      expect(find.text('TWN'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('僅檢查 Wallet 摘要與有效期限'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(CredentialDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('僅檢查 Wallet 摘要與有效期限'), findsOneWidget);
    },
  );

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

  testWidgets('wallet exposes prominent verifier QR scanner entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          holderDid: 'did:plc:abcdefghijklmnop',
          repository: InMemoryWalletRepository(),
          verifierScannerBuilder: (_) =>
              const Scaffold(body: Text('scanner opened')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet_verifier_scan_entry')), findsOneWidget);
    expect(find.text('掃描 QRCode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wallet_verifier_scan_entry')));
    await tester.pumpAndSettle();

    expect(find.text('scanner opened'), findsOneWidget);
  });

  testWidgets('wallet identity add credential expands inline wizard', (
    tester,
  ) async {
    final repo = InMemoryWalletRepository.withCredentials([
      WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.elix.cool',
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

  testWidgets(
    'successful inline MobileMoica issuance reloads wallet and hides wizard',
    (tester) async {
      final repo = InMemoryWalletRepository();
      final launcher = FakeExternalUrlLauncher();
      await tester.pumpWidget(
        MaterialApp(
          home: WalletScreen(
            holderDid: 'did:plc:abcdefghijklmnop',
            repository: repo,
            vcIssuerClient: FakeMobileMoicaIssuerClient(statuses: ['verified']),
            urlLauncher: launcher,
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
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('mobilemoica-national-id-field')),
        'Z123000000',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('開啟 TW FidO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開啟 TW FidO'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(launcher.opened.single.scheme, 'mobilemoica');
      expect(find.byType(CredentialIssuanceWizard), findsNothing);
      await _scrollWallet(tester);
      expect(find.text('MobileMoica Verified Human'), findsOneWidget);
    },
  );
}

Future<void> _scrollWallet(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -520));
  await tester.pumpAndSettle();
}

class FakeMobileMoicaIssuerClient extends VcIssuerClient {
  FakeMobileMoicaIssuerClient({this.statuses = const []})
    : super(baseUrl: 'http://issuer.test');

  final List<String> statuses;
  var _statusIndex = 0;

  @override
  Future<MobileMoicaRPOffer> startMobileMoicaRPFlow({
    required String holderDid,
    required String nationalId,
    required String consentVersion,
    required String consentCopyHash,
    required String locale,
  }) async {
    expect(holderDid, 'did:plc:abcdefghijklmnop');
    expect(nationalId, 'Z123000000');
    expect(consentVersion, 'mobilemoica-rp-v1');
    expect(consentCopyHash, startsWith('sha256:'));
    expect(locale, isNotEmpty);
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
    expect(offerId, 'offer-1');
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
    expect(holderDid, 'did:plc:abcdefghijklmnop');
    expect(offerId, 'offer-1');
    return {
      '@context': ['https://www.w3.org/ns/credentials/v2'],
      'id': 'urn:uuid:inline-humanity',
      'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
      'issuer': 'did:web:issuer.elix.cool',
      'validFrom': '2026-05-05T12:00:00Z',
      'validUntil': '2026-08-03T12:00:00Z',
      'credentialSubject': {'id': 'did:plc:abcdefghijklmnop', 'humanity': true},
      'proof': {
        '@context': ['https://www.w3.org/ns/credentials/v2'],
        'type': 'DataIntegrityProof',
        'cryptosuite': 'eddsa-jcs-2022',
        'created': '2026-05-05T12:00:00Z',
        'verificationMethod': 'did:web:issuer.elix.cool#key-1',
        'proofPurpose': 'assertionMethod',
        'proofValue': 'zabcd',
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
