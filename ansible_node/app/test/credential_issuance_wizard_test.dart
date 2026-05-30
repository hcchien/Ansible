import 'package:ansible_node/screens/credential_issuance_wizard.dart';
import 'package:ansible_node/services/passport_local_id_service.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/vc_issuer_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows TW provider, Passport NFC, and email OTP flow options', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(holderDid: 'did:plc:abcdefghijklmnop'),
        ),
      ),
    );

    expect(find.text('TW 身份驗證'), findsOneWidget);
    expect(find.text('Passport NFC'), findsOneWidget);
    expect(find.text('Email OTP / Legacy'), findsOneWidget);
  });

  testWidgets('selecting TW provider shows MobileMoica disclosure panel', (
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

    expect(find.textContaining('不是 zkID'), findsOneWidget);
    expect(find.text('開啟 TW FidO'), findsOneWidget);
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

    expect(find.text('Email 聯絡方式驗證'), findsOneWidget);
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
    expect(credentials.single.credentialType, 'EmailCredential');
    expect(credentials.single.displayName, 'Email Verified');
    expect(credentials.single.holderDid, 'did:plc:abcdefghijklmnop');
    expect(credentials.single.status, WalletCredentialStatus.active);
    expect(
      await repository.getEncryptedPayload('urn:uuid:email-credential'),
      startsWith('secure-storage-json-v1:'),
    );
    expect(storedCallbackCalled, isTrue);
    expect(reputationTier, 'basic');
    expect(find.text('憑證已加入'), findsOneWidget);
  });

  testWidgets('passport NFC stores v2 VC and local-only extension', (
    tester,
  ) async {
    final repository = InMemoryWalletRepository();
    final client = _FakeVcIssuerClient();
    final localIdService = PassportLocalIdService.fixedSecret('wallet-secret');
    var storedCallbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CredentialIssuanceWizard(
            holderDid: 'did:plc:abcdefghijklmnop',
            walletRepository: repository,
            vcIssuerClient: client,
            passportReader: _FakePassportReader(_passportData),
            passportLocalIdService: localIdService,
            passportZkpProver: const _FakeZkpProver(),
            onCredentialStored: () => storedCallbackCalled = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Passport NFC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('掃描護照 NFC'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.passportIssueCalls, 1);
    expect(client.passportIssuedDid, 'did:plc:abcdefghijklmnop');
    expect(client.passportIssuedNationality, 'TWN');
    expect(client.passportIssuedNationalIdHash, 'national-id-hash-abc123');
    expect(
      client.passportIssuedPassportNumberHash,
      'passport-number-hash-abc123',
    );

    final credentials = await repository.listCredentials();
    expect(credentials, hasLength(1));
    expect(credentials.single.credentialId, 'urn:uuid:passport-credential');
    expect(credentials.single.credentialType, 'TrisAuraHumanityCredential');
    expect(
      await repository.getEncryptedPayload('urn:uuid:passport-credential'),
      startsWith('secure-storage-json-v1:'),
    );

    final localId = localIdService.derive(
      nationality: 'TWN',
      documentNumber: '300012345',
    );
    final extension = await repository.getPassportExtensionByLocalUniqueId(
      localId,
    );
    expect(extension?.credentialId, 'urn:uuid:passport-credential');
    expect(extension?.nationalIdHash, 'national-id-hash-abc123');
    expect(extension?.passportNumberHash, 'passport-number-hash-abc123');
    expect(extension?.nationality, 'TWN');
    expect(extension?.assuranceMethod, 'passport_nfc');
    expect(extension?.toJson().keys, isNot(contains('documentNumber')));
    expect(storedCallbackCalled, isTrue);
    expect(find.text('護照憑證已加入'), findsOneWidget);
  });

  testWidgets(
    'passport NFC blocks duplicate local passport before issuer call',
    (tester) async {
      final repository = InMemoryWalletRepository();
      final localIdService = PassportLocalIdService.fixedSecret(
        'wallet-secret',
      );
      await repository.savePassportExtension(
        PassportWalletExtension(
          credentialId: 'urn:uuid:existing-passport',
          passportLocalUniqueId: localIdService.derive(
            nationality: 'TWN',
            documentNumber: '300012345',
          ),
          nationalIdHash: 'national-id-hash-existing',
          passportNumberHash: 'passport-number-hash-existing',
          nationality: 'TWN',
          assuranceMethod: 'passport_nfc',
          verifiedAt: DateTime.utc(2026, 5, 24),
        ),
      );
      final client = _FakeVcIssuerClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CredentialIssuanceWizard(
              holderDid: 'did:plc:abcdefghijklmnop',
              walletRepository: repository,
              vcIssuerClient: client,
              passportReader: _FakePassportReader(_passportData),
              passportLocalIdService: localIdService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Passport NFC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('掃描護照 NFC'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(client.passportIssueCalls, 0);
      expect(find.text('這本護照已在此 Wallet 驗證過。'), findsOneWidget);
    },
  );
}

class _FakeVcIssuerClient extends VcIssuerClient {
  var passportIssueCalls = 0;
  String? passportIssuedDid;
  String? passportIssuedNationality;
  String? passportIssuedNationalIdHash;
  String? passportIssuedPassportNumberHash;

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

  @override
  Future<Map<String, dynamic>> issuePassportCredential({
    required String did,
    required String nationality,
    required String nationalIdHash,
    required String passportNumberHash,
    required String zkpProof,
    required String zkpCircuitVersion,
    required String verificationKeyHash,
  }) async {
    passportIssueCalls += 1;
    passportIssuedDid = did;
    passportIssuedNationality = nationality;
    passportIssuedNationalIdHash = nationalIdHash;
    passportIssuedPassportNumberHash = passportNumberHash;
    expect(zkpProof, 'proof-abc123');
    expect(zkpCircuitVersion, ZkpProof.kCircuitVersion);
    expect(verificationKeyHash, 'sha256:vk-hash-abc123');
    return _passportCredentialJson;
  }
}

class _FakeRelayClient extends AtProtoClient {
  @override
  Future<String> presentVp({
    required String holderDid,
    required Map<String, dynamic> vp,
    Map<String, dynamic>? nostrBinding,
  }) async {
    expect(holderDid, 'did:plc:abcdefghijklmnop');
    expect(vp['holder'], holderDid);
    expect(nostrBinding, isNull);
    return 'basic';
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

class _FakePassportReader implements NfcPassportReader {
  _FakePassportReader(this.data);

  final PassportData data;

  @override
  Future<void> scan({
    required void Function(PassportData) onPassportRead,
    required void Function(String) onError,
  }) async {
    onPassportRead(data);
  }

  @override
  Future<void> cancel() async {}
}

class _FakeZkpProver implements ZkpProver {
  const _FakeZkpProver();

  @override
  Future<ZkpProof> prove({required String passportSecretHex}) async {
    expect(passportSecretHex, _passportData.passportSecret);
    return const ZkpProof(
      backend: 'groth16_bn254',
      proofHex: 'proof-abc123',
      nullifierHex: 'passport-nullifier-abc123',
      vkHash: 'vk-hash-abc123',
      nationalIdHash: 'national-id-hash-abc123',
      passportNumberHash: 'passport-number-hash-abc123',
    );
  }
}

const _passportData = PassportData(
  documentNumber: '300012345',
  dateOfBirth: '900101',
  dateOfExpiry: '300101',
  nationality: 'TWN',
  dg1Bytes: [],
  sodBytes: [],
  passportSecret: 'dev-secret',
);

final _emailCredentialJson = <String, dynamic>{
  '@context': ['https://www.w3.org/2018/credentials/v1'],
  'id': 'urn:uuid:email-credential',
  'type': ['VerifiableCredential', 'EmailCredential'],
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

final _passportCredentialJson = <String, dynamic>{
  '@context': [
    'https://www.w3.org/ns/credentials/v2',
    'https://trisaura.io/contexts/humanity/v1',
  ],
  'id': 'urn:uuid:passport-credential',
  'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
  'issuer': 'did:web:issuer.trisaura.io',
  'validFrom': '2026-05-24T00:00:00Z',
  'validUntil': '2026-08-22T00:00:00Z',
  'credentialSubject': {
    'id': 'did:plc:abcdefghijklmnop',
    'humanVerified': true,
    'assuranceLevel': 'passport_document',
    'assuranceMethod': 'passport_nfc',
    'nationality': 'TWN',
  },
  'proof': {
    'type': 'Ed25519Signature2020',
    'created': '2026-05-24T00:00:00Z',
    'verificationMethod': 'did:web:issuer.trisaura.io#key-1',
    'proofPurpose': 'assertionMethod',
    'proofValue': 'issuer-proof',
  },
};
