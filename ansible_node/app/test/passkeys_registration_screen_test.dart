import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/screens/passkeys_registration_screen.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/services/platform_capabilities.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'registration mints a self-certifying did:elix and anchors it with the relay',
    (tester) async {
      final passkeyPublicKey = 'ab' * 32;
      final passkeys = _FakePasskeysManager(passkeyPublicKey);
      final store = InMemoryCanonicalIdentityStore();
      final atProto = _FakeAtProtoClient();
      String? registeredDid;
      String? signedNonce;
      String? signingPublicKey;

      await tester.pumpWidget(
        MaterialApp(
          home: PasskeysRegistrationScreen(
            passkeysManager: passkeys,
            canonicalIdentityStore: store,
            atProtoClient: atProto,
            nonceSigner: (nonce, publicKeyHex) async {
              signedNonce = nonce;
              signingPublicKey = publicKeyHex;
              return 'sig-for-$nonce';
            },
            onRegistered: (did, handle) => registeredDid = did,
          ),
        ),
      );

      await tester.tap(find.text('建立身分並啟用裝置保護'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      final commitment = atProto.anchorRequest!.genesisCommitment!;
      final expectedDid = deriveDidElixV1(
        genesisKey: passkeyPublicKey,
        genesisNonceHex: commitment['genesis_nonce']! as String,
      );
      final expectedProof = didElixV1RegistrationPayload(
        nonce: 'nonce-1',
        did: expectedDid,
        genesisCommitment: commitment,
      );
      expect(expectedDid, startsWith('did:elix:z'));
      expect(atProto.registeredPublicKeyHex, passkeyPublicKey);
      expect(atProto.anchorRequest?.did, expectedDid);
      expect(atProto.anchorRequest?.publicKeyHex, passkeyPublicKey);
      expect(atProto.anchorRequest?.registrationSig, 'sig-for-$expectedProof');
      expect(atProto.anchorRequest?.nonce, 'nonce-1');
      expect(signedNonce, expectedProof);
      expect(signingPublicKey, passkeyPublicKey);
      expect(registeredDid, expectedDid);

      // The canonical identity is persisted for subsequent launches.
      final persisted = await store.load();
      expect(persisted?.did, expectedDid);
      expect(persisted?.handle, 'user.elix.cool');
      expect(persisted?.publicKeyHex, passkeyPublicKey);
      expect(persisted?.genesisCommitment, commitment);
    },
  );

  testWidgets('registration surfaces relay errors without completing', (
    tester,
  ) async {
    final passkeys = _FakePasskeysManager('cd' * 32);
    final store = InMemoryCanonicalIdentityStore();
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
          canonicalIdentityStore: store,
          atProtoClient: atProto,
          nonceSigner: (nonce, publicKeyHex) async => 'unused',
          onRegistered: (did, handle) => registeredDid = did,
        ),
      ),
    );

    await tester.tap(find.text('建立身分並啟用裝置保護'));
    await tester.pumpAndSettle();

    expect(find.text('此帳號名稱已被使用，請嘗試不同的名稱。'), findsOneWidget);
    expect(registeredDid, isNull);
    expect(await store.load(), isNull);
    expect(passkeys.deleteCalled, isTrue);
  });

  testWidgets('registration converts Dart fallback signer output in dev mode', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'ansible_did_private_key': '11' * 32,
    });

    final passkeys = _FakePasskeysManager('cd' * 32);
    final store = InMemoryCanonicalIdentityStore();
    final atProto = _FakeAtProtoClient();
    String? registeredDid;

    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          passkeysManager: passkeys,
          canonicalIdentityStore: store,
          atProtoClient: atProto,
          allowInsecureDevFallback: true,
          onRegistered: (did, handle) => registeredDid = did,
        ),
      ),
    );

    await tester.tap(find.text('建立身分並啟用裝置保護'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(atProto.anchorRequest?.registrationSig, startsWith('dev-sig-'));
    expect(registeredDid, startsWith('did:elix:z'));
    expect(atProto.anchorRequest?.genesisCommitment, isNotNull);
  });

  testWidgets('registration can complete locally when dev relay is offline', (
    tester,
  ) async {
    final passkeys = _FakePasskeysManager('cd' * 32);
    final store = InMemoryCanonicalIdentityStore();
    final atProto = _OfflineAtProtoClient();
    String? registeredDid;

    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          passkeysManager: passkeys,
          canonicalIdentityStore: store,
          atProtoClient: atProto,
          allowInsecureDevFallback: true,
          onRegistered: (did, handle) => registeredDid = did,
        ),
      ),
    );

    await tester.tap(find.text('建立身分並啟用裝置保護'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(atProto.registerCalled, isTrue);
    expect(registeredDid, startsWith('did:elix:z'));
    expect(await store.load(), isNotNull);
    expect(passkeys.deleteCalled, isFalse);
  });

  testWidgets('registration still surfaces relay rejection in dev mode', (
    tester,
  ) async {
    final passkeys = _FakePasskeysManager('cd' * 32);
    final store = InMemoryCanonicalIdentityStore();
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
          canonicalIdentityStore: store,
          atProtoClient: atProto,
          allowInsecureDevFallback: true,
          nonceSigner: (nonce, publicKeyHex) async => 'unused',
          onRegistered: (did, handle) => registeredDid = did,
        ),
      ),
    );

    await tester.tap(find.text('建立身分並啟用裝置保護'));
    await tester.pumpAndSettle();

    expect(find.text('此帳號名稱已被使用，請嘗試不同的名稱。'), findsOneWidget);
    expect(registeredDid, isNull);
  });

  testWidgets(
    'registration shows the recover-existing-account affordance and opens it',
    (tester) async {
      var recoverTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PasskeysRegistrationScreen(
            passkeysManager: _FakePasskeysManager('ab' * 32),
            canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
            atProtoClient: _FakeAtProtoClient(),
            nonceSigner: (nonce, publicKeyHex) async => 'unused',
            onRegistered: (did, handle) {},
            onRecoverExistingAccount: () => recoverTapped = true,
          ),
        ),
      );

      // zh-Hant copy (test locale falls back to zh-Hant).
      expect(find.text('已經有帳號？在這台裝置使用或復原'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('recover_existing_account_button')),
      );
      await tester.pump();
      expect(recoverTapped, isTrue);
    },
  );

  testWidgets('recover affordance is hidden when no handler is wired', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          passkeysManager: _FakePasskeysManager('ab' * 32),
          canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
          atProtoClient: _FakeAtProtoClient(),
          onRegistered: (did, handle) {},
        ),
      ),
    );
    expect(
      find.byKey(const Key('recover_existing_account_button')),
      findsNothing,
    );
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
          canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
          atProtoClient: atProto,
          nonceSigner: (nonce, publicKeyHex) async => 'unused',
          onRegistered: (did, handle) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '-bad');
    await tester.tap(find.text('建立身分並啟用裝置保護'));
    await tester.pump();

    expect(find.text('帳號名稱格式無效，請使用 1–63 個英數字或中間連字號。'), findsOneWidget);
    expect(passkeys.registerCalled, isFalse);
    expect(atProto.registeredPublicKeyHex, isNull);
  });
  testWidgets('reduced-trust desktop requires explicit consent', (
    tester,
  ) async {
    final passkeys = _FakePasskeysManager('ef' * 32);

    await tester.pumpWidget(
      MaterialApp(
        home: PasskeysRegistrationScreen(
          platformCapabilities: PlatformCapabilities.forPlatform(
            ElixPlatform.windows,
          ),
          passkeysManager: passkeys,
          canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
          atProtoClient: _FakeAtProtoClient(),
          nonceSigner: (nonce, publicKeyHex) async => 'sig-for-$nonce',
          onRegistered: (did, handle) {},
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('create_identity_button')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byKey(const Key('reduced_trust_identity_consent')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('reduced_trust_identity_consent')),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final enabled = tester.widget<FilledButton>(
      find.byKey(const Key('create_identity_button')),
    );
    expect(enabled.onPressed, isNotNull);
  });
  testWidgets(
    'onboarding follows the app theme instead of a fixed Paper palette',
    (tester) async {
      // Regression: the screen used to hard-code the light constants, so under
      // the Ink theme it rendered a light page with a dark, theme-driven handle
      // field sitting in the middle of it.
      await tester.pumpWidget(
        MaterialApp(
          theme: AnsibleDesign.theme(),
          darkTheme: AnsibleDesign.darkTheme(),
          themeMode: ThemeMode.dark,
          home: PasskeysRegistrationScreen(
            passkeysManager: _FakePasskeysManager('cd' * 32),
            canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
            atProtoClient: _FakeAtProtoClient(),
            onRegistered: (_, _) {},
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AnsibleDesign.darkPaper);

      final field = tester.widget<TextField>(find.byType(TextField));
      final fill =
          field.decoration?.fillColor ??
          Theme.of(
            tester.element(find.byType(TextField)),
          ).inputDecorationTheme.fillColor;
      // The handle field must sit on the same ground as the screen around it.
      expect(fill, AnsibleDesign.darkPaperElev);
    },
  );
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
  Future<PasskeysCredential> register({
    required String username,
    bool reuseHardwareAuthenticationContext = false,
  }) async {
    registerCalled = true;
    return PasskeysCredential(
      did: 'did:key:test',
      publicKeyHex: publicKeyHex,
      handle: username,
    );
  }
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
    String? did,
    String signingAlgorithm = 'ed25519',
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

class _OfflineAtProtoClient extends AtProtoClient {
  bool registerCalled = false;

  _OfflineAtProtoClient() : super(baseUrl: 'http://unused.local');

  @override
  Future<RegistrationChallenge> register({
    required String publicKeyHex,
    required String handleSuffix,
    String? did,
    String signingAlgorithm = 'ed25519',
  }) async {
    registerCalled = true;
    throw Exception('Relay is offline');
  }
}
