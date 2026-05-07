import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/screens/passkeys_registration_screen.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'registration reuses the passkeys public key across did:plc and relay anchor',
    (tester) async {
      final passkeyPublicKey = 'ab' * 32;
      final passkeys = _FakePasskeysManager(passkeyPublicKey);
      final didPlc = _FakeDidPlcManager();
      final atProto = _FakeAtProtoClient();
      String? registeredDid;
      String? signedNonce;
      String? signingPublicKey;

      await tester.pumpWidget(
        MaterialApp(
          home: PasskeysRegistrationScreen(
            passkeysManager: passkeys,
            didPlcManager: didPlc,
            atProtoClient: atProto,
            nonceSigner: (nonce, publicKeyHex) async {
              signedNonce = nonce;
              signingPublicKey = publicKeyHex;
              return 'sig-for-$nonce';
            },
            onRegistered: (did) => registeredDid = did,
          ),
        ),
      );

      await tester.tap(find.text('建立帳號（Passkeys）'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(didPlc.signingKeyHex, passkeyPublicKey);
      expect(atProto.registeredPublicKeyHex, passkeyPublicKey);
      expect(atProto.anchorRequest?.did, 'did:plc:test');
      expect(atProto.anchorRequest?.publicKeyHex, passkeyPublicKey);
      expect(atProto.anchorRequest?.registrationSig, 'sig-for-nonce-1');
      expect(atProto.anchorRequest?.nonce, 'nonce-1');
      expect(signedNonce, 'nonce-1');
      expect(signingPublicKey, passkeyPublicKey);
      expect(registeredDid, 'did:plc:test');
    },
  );

  testWidgets('registration surfaces relay errors without completing', (
    tester,
  ) async {
    final passkeys = _FakePasskeysManager('cd' * 32);
    final didPlc = _FakeDidPlcManager();
    final atProto = _FakeAtProtoClient(
      registerError: const AtProtoException(
        statusCode: 409,
        error: 'handle_taken',
      ),
    );
    String? registeredDid;

    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          passkeysManager: passkeys,
          didPlcManager: didPlc,
          atProtoClient: atProto,
          nonceSigner: (nonce, publicKeyHex) async => 'unused',
          onRegistered: (did) => registeredDid = did,
        ),
      ),
    );

    await tester.tap(find.text('建立帳號（Passkeys）'));
    await tester.pumpAndSettle();

    expect(find.text('此帳號名稱已被使用，請嘗試不同的名稱。'), findsOneWidget);
    expect(registeredDid, isNull);
    expect(didPlc.deleteCalled, isTrue);
    expect(passkeys.deleteCalled, isTrue);
  });

  testWidgets('registration converts Dart fallback signer output in dev mode', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'ansible_did_private_key': '11' * 32,
    });

    final passkeys = _FakePasskeysManager('cd' * 32);
    final didPlc = _FakeDidPlcManager();
    final atProto = _FakeAtProtoClient();
    String? registeredDid;

    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          passkeysManager: passkeys,
          didPlcManager: didPlc,
          atProtoClient: atProto,
          allowInsecureDevFallback: true,
          onRegistered: (did) => registeredDid = did,
        ),
      ),
    );

    await tester.tap(find.text('建立帳號（Passkeys）'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(atProto.anchorRequest?.registrationSig, startsWith('dev-sig-'));
    expect(registeredDid, 'did:plc:test');
  });

  testWidgets('registration validates handle suffix before generating keys', (
    tester,
  ) async {
    final passkeys = _FakePasskeysManager('ef' * 32);
    final atProto = _FakeAtProtoClient();

    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          passkeysManager: passkeys,
          didPlcManager: _FakeDidPlcManager(),
          atProtoClient: atProto,
          nonceSigner: (nonce, publicKeyHex) async => 'unused',
          onRegistered: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '-bad');
    await tester.tap(find.text('建立帳號（Passkeys）'));
    await tester.pump();

    expect(find.text('帳號名稱格式無效，請使用 1–63 個英數字或中間連字號。'), findsOneWidget);
    expect(passkeys.registerCalled, isFalse);
    expect(atProto.registeredPublicKeyHex, isNull);
  });
}

class _FakePasskeysManager implements PasskeysManager {
  final String publicKeyHex;
  bool registerCalled = false;
  bool deleteCalled = false;

  _FakePasskeysManager(this.publicKeyHex);

  @override
  Future<void> delete() async {
    deleteCalled = true;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PasskeysCredential?> load() async => null;

  @override
  Future<PasskeysCredential> register({required String username}) async {
    registerCalled = true;
    return PasskeysCredential(
      did: 'did:key:test',
      publicKeyHex: publicKeyHex,
      handle: username,
    );
  }
}

class _FakeDidPlcManager implements DidPlcManager {
  String? signingKeyHex;
  bool deleteCalled = false;

  @override
  Future<DidPlcResult> createDid({
    required String handle,
    String pdsEndpoint = 'https://trisaura.io',
    String? signingKeyHex,
  }) async {
    this.signingKeyHex = signingKeyHex;
    return DidPlcResult(
      did: 'did:plc:test',
      genesisJson: '{"type":"plc_genesis"}',
      publicKeyHex: signingKeyHex ?? '00' * 32,
    );
  }

  @override
  Future<void> deleteDid() async {
    deleteCalled = true;
  }

  @override
  Future<DidPlcResult?> loadDid() async => null;
}

class _FakeAtProtoClient extends AtProtoClient {
  final AtProtoException? registerError;
  String? registeredPublicKeyHex;
  AnchorRequest? anchorRequest;

  _FakeAtProtoClient({this.registerError})
    : super(baseUrl: 'http://unused.local');

  @override
  Future<RegistrationChallenge> register({
    required String publicKeyHex,
    required String handleSuffix,
  }) async {
    final error = registerError;
    if (error != null) throw error;
    registeredPublicKeyHex = publicKeyHex;
    expect(handleSuffix, 'user');
    return const RegistrationChallenge(
      nonce: 'nonce-1',
      expiresAt: '2026-05-04T00:00:00Z',
    );
  }

  @override
  Future<AnchoredDid> anchor(AnchorRequest req) async {
    anchorRequest = req;
    return AnchoredDid(
      did: req.did,
      handle: req.handle,
      expiresAt: '2026-08-04T00:00:00Z',
    );
  }
}
