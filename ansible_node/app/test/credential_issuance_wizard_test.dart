import 'package:ansible_node/screens/credential_issuance_wizard.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows TW provider and email OTP flow options', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(holderDid: 'did:plc:abcdefghijklmnop'),
        ),
      ),
    );

    expect(find.text('TW 身份驗證'), findsOneWidget);
    expect(find.text('Email OTP / Legacy'), findsOneWidget);
  });

  testWidgets('selecting TW provider shows provider flow panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(
            holderDid: 'did:plc:abcdefghijklmnop',
            walletRepository: InMemoryWalletRepository(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('TW 身份驗證'));
    await tester.pumpAndSettle();

    expect(find.text('開始驗證'), findsOneWidget);
  });

  testWidgets('selecting email shows email OTP panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(
            holderDid: 'did:plc:abcdefghijklmnop',
            walletRepository: InMemoryWalletRepository(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Email OTP / Legacy'));
    await tester.pumpAndSettle();

    expect(find.text('Email 身份驗證'), findsOneWidget);
  });

  testWidgets('email OTP stores issued VC in wallet repository', (
    tester,
  ) async {
    final repository = InMemoryWalletRepository();
    var storedCallbackCalled = false;
    String? reputationTier;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(
            holderDid: 'did:plc:abcdefghijklmnop',
            walletRepository: repository,
            vcIssuerClient: _FakeVcIssuerClient(),
            relayClient: _FakeRelayClient(),
            credentialWallet: const _FakeCredentialWallet(),
            vpBuilder: _FakeVpBuilder(),
            onCredentialStored: () => storedCallbackCalled = true,
            onEmailCredentialAdded: (tier) => reputationTier = tier,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Email OTP / Legacy'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.tap(find.text('發送驗證碼'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('123456'), findsOneWidget);

    await tester.ensureVisible(find.text('驗證並取得憑證'));
    await tester.tap(find.text('驗證並取得憑證'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final credentials = await repository.listCredentials();
    expect(credentials, hasLength(1));
    expect(credentials.single.credentialId, 'urn:uuid:email-credential');
    expect(credentials.single.credentialType, 'TrisAuraHumanityCredential');
    expect(credentials.single.holderDid, 'did:plc:abcdefghijklmnop');
    expect(credentials.single.status, WalletCredentialStatus.active);
    expect(
      await repository.getEncryptedPayload('urn:uuid:email-credential'),
      contains('"credentialSubject"'),
    );
    expect(storedCallbackCalled, isTrue);
    expect(reputationTier, 'verified_human');
    expect(find.text('憑證已加入'), findsOneWidget);
  });
}

class _FakeVcIssuerClient extends VcIssuerClient {
  @override
  Future<VcIssuanceChallenge> requestEmailVerification({
    required String did,
    required String email,
  }) async {
    expect(did, 'did:plc:abcdefghijklmnop');
    expect(email, 'user@example.com');
    return const VcIssuanceChallenge(hint: 'mock', otp: '123456');
  }

  @override
  Future<Map<String, dynamic>> issueCredential({
    required String did,
    required String email,
    required String otp,
  }) async {
    expect(did, 'did:plc:abcdefghijklmnop');
    expect(email, 'user@example.com');
    expect(otp, '123456');
    return _emailCredentialJson;
  }
}

class _FakeRelayClient extends AtProtoClient {
  @override
  Future<String> presentVp({
    required String holderDid,
    required Map<String, dynamic> vp,
  }) async {
    expect(holderDid, 'did:plc:abcdefghijklmnop');
    expect(vp['holder'], holderDid);
    return 'verified_human';
  }
}

class _FakeCredentialWallet extends CredentialWallet {
  const _FakeCredentialWallet();

  @override
  Future<void> store(VerifiableCredential vc) async {}
}

class _FakeVpBuilder extends VpBuilder {
  @override
  Future<VerifiablePresentation> build({
    required String holderDid,
    required List<VerifiableCredential> credentials,
  }) async {
    return VerifiablePresentation(
      context: const ['https://www.w3.org/2018/credentials/v1'],
      type: const ['VerifiablePresentation'],
      holder: holderDid,
      verifiableCredential: credentials,
      proof: const CredentialProof(
        type: 'Ed25519Signature2020',
        created: '2026-05-10T00:00:00Z',
        verificationMethod: 'did:plc:abcdefghijklmnop#key-1',
        proofPurpose: 'authentication',
        proofValue: 'test-proof',
      ),
    );
  }
}

final _emailCredentialJson = <String, dynamic>{
  '@context': ['https://www.w3.org/2018/credentials/v1'],
  'id': 'urn:uuid:email-credential',
  'type': [
    'VerifiableCredential',
    'TrisAuraHumanityCredential',
    'EmailCredential',
  ],
  'issuer': 'did:web:issuer.trisaura.io',
  'issuanceDate': '2026-05-10T00:00:00Z',
  'expirationDate': '2026-08-08T00:00:00Z',
  'credentialSubject': {'id': 'did:plc:abcdefghijklmnop', 'emailHash': 'hash'},
  'proof': {
    'type': 'Ed25519Signature2020',
    'created': '2026-05-10T00:00:00Z',
    'verificationMethod': 'did:web:issuer.trisaura.io#key-1',
    'proofPurpose': 'assertionMethod',
    'proofValue': 'issuer-proof',
  },
};
