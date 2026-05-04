# Taiwan Digital Identity VC Wallet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Tris-Aura Wallet support so the App can store, present, and refresh Tris-Aura-issued VCs backed by Taiwan natural-person-certificate identity proofing.

**Architecture:** Start with deterministic local fixtures and a mock identity-provider adapter, then replace the adapter with the approved TW FidO/MOICA integration. Keep raw government identity at the issuer boundary; the App stores only signed VCs and presentation history.

**Tech Stack:** Flutter/Dart app, Drift SQLite store, Dart relay/server modules, DID/VC helper package, Ed25519 signatures, future OID4VCI/OID4VP compatibility.

---

## File Structure

- Create `ansible_core/store/lib/src/entities/wallet_credential.dart`: immutable Wallet credential metadata entity.
- Create `ansible_core/store/lib/src/entities/wallet_presentation.dart`: local presentation audit entity.
- Create `ansible_core/store/lib/src/schema/wallet_credentials.dart`: Drift table for metadata.
- Create `ansible_core/store/lib/src/schema/wallet_credential_payloads.dart`: Drift table for encrypted VC payloads.
- Create `ansible_core/store/lib/src/schema/wallet_presentations.dart`: Drift table for local presentation audit.
- Create `ansible_core/store/lib/src/repositories/wallet_repository.dart`: Wallet repository interface.
- Create `ansible_core/store/lib/src/repositories/drift/drift_wallet_repository.dart`: Drift-backed implementation.
- Create `ansible_core/store/lib/src/repositories/in_memory/in_memory_wallet_repository.dart`: in-memory implementation for UI tests.
- Modify `ansible_core/store/lib/src/db/app_database.dart`: add Wallet tables and bump schema version.
- Modify `ansible_core/store/lib/ansible_store.dart`: export Wallet entities and repository.
- Create `ansible_core/vc/lib/src/tris_aura_credential.dart`: VC model and parser.
- Create `ansible_core/vc/lib/src/vc_verifier.dart`: issuer, holder, expiry, and status verification facade.
- Create `ansible_core/vc/lib/src/vp_builder.dart`: challenge/audience-bound VP builder.
- Create `ansible_core/vc/test/fixtures/humanity_credential_fixtures.dart`: valid and expired credential fixtures.
- Modify `ansible_core/vc/lib/ansible_vc.dart`: export new VC/VP types.
- Create `ansible_node/app/lib/services/vc_issuer_client.dart`: App client for offer/issue/status endpoints.
- Create `ansible_node/app/lib/services/vc_presentation_service.dart`: App service for building VPs from local Wallet data.
- Create `ansible_node/app/lib/screens/wallet_screen.dart`: Wallet list/detail/add/delete UI.
- Create `ansible_node/app/lib/screens/presentation_approval_screen.dart`: explicit VP approval UI.
- Modify `ansible_node/app/lib/screens/home_shell.dart`: add Wallet navigation entry.
- Create `ansible_relay/server/lib/src/vc/subject_commitment.dart`: HMAC duplicate-prevention commitment.
- Create `ansible_relay/server/lib/src/vc/tw_identity_provider.dart`: behaviour/interface plus mock adapter.
- Create `ansible_relay/server/lib/src/vc/vc_issuer.dart`: offer/session/issue logic.
- Create `ansible_relay/server/lib/src/vc/vc_credential_store.dart`: issued credential and status persistence.
- Create `ansible_relay/server/lib/src/handlers/vc_handler.dart`: HTTP endpoints.
- Modify `ansible_relay/server/lib/src/router.dart`: route VC endpoints.

## Task 1: Wallet Store

**Files:**

- Create: `ansible_core/store/lib/src/entities/wallet_credential.dart`
- Create: `ansible_core/store/lib/src/entities/wallet_presentation.dart`
- Create: `ansible_core/store/lib/src/schema/wallet_credentials.dart`
- Create: `ansible_core/store/lib/src/schema/wallet_credential_payloads.dart`
- Create: `ansible_core/store/lib/src/schema/wallet_presentations.dart`
- Create: `ansible_core/store/lib/src/repositories/wallet_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/drift/drift_wallet_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/in_memory/in_memory_wallet_repository.dart`
- Modify: `ansible_core/store/lib/src/db/app_database.dart`
- Modify: `ansible_core/store/lib/ansible_store.dart`
- Test: `ansible_core/store/test/drift_wallet_repository_test.dart`

- [ ] **Step 1: Write repository tests**

```dart
test('stores encrypted credential payload separately from metadata', () async {
  final db = AppDatabase(NativeDatabase.memory());
  final repo = DriftWalletRepository(db);

  await repo.saveCredential(
    metadata: WalletCredential(
      credentialId: 'urn:uuid:test-humanity',
      issuerDid: 'did:web:issuer.trisaura.io',
      holderDid: 'did:key:z6Mkholder',
      credentialType: 'TrisAuraHumanityCredential',
      status: 'active',
      validFrom: DateTime.utc(2026, 5, 4),
      validUntil: DateTime.utc(2026, 8, 2),
      displayName: 'Verified Human',
    ),
    encryptedPayload: 'ciphertext-not-json',
    encryptionVersion: 'local-dev-v1',
  );

  final credentials = await repo.listCredentials();
  expect(credentials.single.credentialId, 'urn:uuid:test-humanity');
  expect(credentials.single.displayName, 'Verified Human');

  final payload = await repo.getEncryptedPayload('urn:uuid:test-humanity');
  expect(payload, 'ciphertext-not-json');
  expect(payload, isNot(contains('humanVerified')));
});

test('records presentation metadata without claim payloads', () async {
  final db = AppDatabase(NativeDatabase.memory());
  final repo = DriftWalletRepository(db);

  await repo.recordPresentation(
    WalletPresentation(
      presentationId: 'vp-1',
      credentialId: 'urn:uuid:test-humanity',
      verifierAudience: 'https://relay.trisaura.io',
      nonceHash: 'sha256-nonce',
      result: 'approved',
      createdAt: DateTime.utc(2026, 5, 4, 10),
    ),
  );

  final history = await repo.listPresentations('urn:uuid:test-humanity');
  expect(history.single.result, 'approved');
  expect(history.single.nonceHash, 'sha256-nonce');
});
```

- [ ] **Step 2: Run failing store tests**

Run: `cd ansible_core/store && dart test test/drift_wallet_repository_test.dart`

Expected: fails because Wallet entities, tables, and repository do not exist.

- [ ] **Step 3: Implement Wallet tables and repository**

Use the schema in `docs/protocol/tris_aura_vc_wallet_spec_v0.1.md` section 5.
Bump `AppDatabase.schemaVersion` by one, add the three Wallet tables to
`@DriftDatabase`, and create them in `onUpgrade`.

- [ ] **Step 4: Export Wallet types**

Export the new entity and repository files from `ansible_core/store/lib/ansible_store.dart`.

- [ ] **Step 5: Run store tests**

Run: `cd ansible_core/store && dart test test/drift_wallet_repository_test.dart`

Expected: all Wallet repository tests pass.

## Task 2: VC Model And Verification

**Files:**

- Create: `ansible_core/vc/lib/src/tris_aura_credential.dart`
- Create: `ansible_core/vc/lib/src/vc_verifier.dart`
- Create: `ansible_core/vc/lib/src/vp_builder.dart`
- Create: `ansible_core/vc/test/fixtures/humanity_credential_fixtures.dart`
- Modify: `ansible_core/vc/lib/ansible_vc.dart`
- Test: `ansible_core/vc/test/tris_aura_credential_test.dart`
- Test: `ansible_core/vc/test/vp_builder_test.dart`

- [ ] **Step 1: Write credential parser tests**

```dart
test('parses a humanity credential without exposing prohibited claims', () {
  final credential = TrisAuraCredential.fromJson(humanityFixture);

  expect(credential.id, 'urn:uuid:test-humanity');
  expect(credential.holderDid, 'did:key:z6Mkholder');
  expect(credential.type, contains('TrisAuraHumanityCredential'));
  expect(credential.claims['humanVerified'], true);
  expect(credential.claims.containsKey('nationalId'), isFalse);
  expect(credential.claims.containsKey('legalName'), isFalse);
});

test('expired credential fails verification result', () {
  final credential = TrisAuraCredential.fromJson(expiredHumanityFixture);
  final result = VcVerifier.verifyCredential(
    credential,
    now: DateTime.utc(2026, 9, 1),
    trustedIssuers: {'did:web:issuer.trisaura.io'},
    status: CredentialStatus.active,
  );

  expect(result.isValid, isFalse);
  expect(result.error, 'credential_expired');
});
```

- [ ] **Step 2: Write VP builder tests**

```dart
test('builds presentation bound to nonce and audience', () {
  final vp = VpBuilder.build(
    credential: TrisAuraCredential.fromJson(humanityFixture),
    holderDid: 'did:key:z6Mkholder',
    nonce: 'nonce-123',
    audience: 'https://relay.trisaura.io',
    proofValue: 'test-signature',
  );

  expect(vp['holder'], 'did:key:z6Mkholder');
  expect(vp['proof']['challenge'], 'nonce-123');
  expect(vp['proof']['domain'], 'https://relay.trisaura.io');
});
```

- [ ] **Step 3: Run failing VC tests**

Run: `cd ansible_core/vc && dart test`

Expected: fails because VC model and VP builder do not exist.

- [ ] **Step 4: Implement parser, verifier, and VP builder**

Implement deterministic JSON parsing and a `ProofVerifier` interface. Unit tests
should inject `FakeProofVerifier.valid()` and `FakeProofVerifier.invalid()` so
expiry, issuer allowlist, holder binding, credential type, status, and proof
failure are all covered before the production signing bridge is connected.

- [ ] **Step 5: Run VC tests**

Run: `cd ansible_core/vc && dart test`

Expected: parser, verifier, and VP builder tests pass.

## Task 3: App Wallet UI And Services

**Files:**

- Create: `ansible_node/app/lib/services/vc_issuer_client.dart`
- Create: `ansible_node/app/lib/services/vc_presentation_service.dart`
- Create: `ansible_node/app/lib/screens/wallet_screen.dart`
- Create: `ansible_node/app/lib/screens/presentation_approval_screen.dart`
- Create: `ansible_node/app/test/support/fake_http_client.dart`
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Test: `ansible_node/app/test/vc_issuer_client_test.dart`
- Test: `ansible_node/app/test/wallet_screen_test.dart`

- [ ] **Step 1: Write issuer client tests**

```dart
test('creates credential offer request with holder DID and requested type', () async {
  final client = VcIssuerClient(
    baseUrl: Uri.parse('https://relay.trisaura.io'),
    httpClient: fakeHttpClient((request) {
      expect(request.path, '/api/v1/vc/offer');
      expect(request.json['holder_did'], 'did:key:z6Mkholder');
      expect(request.json['requested_types'], ['TrisAuraHumanityCredential']);
      return {
        'offer_id': 'vc-offer-test',
        'issuer': 'did:web:issuer.trisaura.io',
        'expires_at': '2026-05-04T10:15:00Z',
        'auth_request': {'mode': 'mock', 'mock_assertion_token': 'test-only'}
      };
    }),
  );

  final offer = await client.createOffer(
    holderDid: 'did:key:z6Mkholder',
    requestedTypes: ['TrisAuraHumanityCredential'],
  );

  expect(offer.offerId, 'vc-offer-test');
  expect(offer.authRequest.mode, 'mock');
});
```

- [ ] **Step 2: Write Wallet screen tests**

```dart
testWidgets('wallet screen lists credential status and expiry', (tester) async {
  final repo = InMemoryWalletRepository.withCredentials([
    WalletCredential(
      credentialId: 'urn:uuid:test-humanity',
      issuerDid: 'did:web:issuer.trisaura.io',
      holderDid: 'did:key:z6Mkholder',
      credentialType: 'TrisAuraHumanityCredential',
      status: 'active',
      validFrom: DateTime.utc(2026, 5, 4),
      validUntil: DateTime.utc(2026, 8, 2),
      displayName: 'Verified Human',
    ),
  ]);

  await tester.pumpWidget(MaterialApp(home: WalletScreen(repository: repo)));

  expect(find.text('Verified Human'), findsOneWidget);
  expect(find.textContaining('Active'), findsOneWidget);
  expect(find.textContaining('2026-08-02'), findsOneWidget);
});
```

- [ ] **Step 3: Run failing app tests**

Run: `cd ansible_node/app && flutter test test/vc_issuer_client_test.dart test/wallet_screen_test.dart`

Expected: fails because services and screens do not exist.

- [ ] **Step 4: Implement services and Wallet UI**

Implement offer/issue/status methods, Wallet list/detail/delete UI, and explicit
presentation approval. Keep copy factual: "Verified Human" means Tris-Aura has
issued a credential after Taiwan digital identity proofing; it is not a legal
identity display.

- [ ] **Step 5: Run app tests**

Run: `cd ansible_node/app && flutter test test/vc_issuer_client_test.dart test/wallet_screen_test.dart`

Expected: Wallet services and UI tests pass.

## Task 4: Issuer MVP With Mock Provider

**Files:**

- Create: `ansible_relay/server/lib/src/vc/subject_commitment.dart`
- Create: `ansible_relay/server/lib/src/vc/tw_identity_provider.dart`
- Create: `ansible_relay/server/lib/src/vc/vc_issuer.dart`
- Create: `ansible_relay/server/lib/src/vc/vc_credential_store.dart`
- Create: `ansible_relay/server/lib/src/handlers/vc_handler.dart`
- Modify: `ansible_relay/server/lib/src/router.dart`
- Test: `ansible_relay/server/test/vc_issuer_test.dart`
- Test: `ansible_relay/server/test/vc_handler_test.dart`

- [ ] **Step 1: Write subject commitment tests**

```dart
test('commitment is deterministic and does not expose provider subject', () {
  final commitment = SubjectCommitment.compute(
    pepper: 'test-pepper',
    providerSubject: 'A123456789',
    assuranceContext: 'tw_natural_person_certificate',
  );

  expect(commitment, SubjectCommitment.compute(
    pepper: 'test-pepper',
    providerSubject: 'A123456789',
    assuranceContext: 'tw_natural_person_certificate',
  ));
  expect(commitment, isNot(contains('A123456789')));
});
```

- [ ] **Step 2: Write issuance tests**

```dart
test('issuer refuses duplicate active humanity credential', () async {
  final issuer = VcIssuer(
    identityProvider: MockTwIdentityProvider.verified(providerSubject: 'subject-1'),
    store: InMemoryVcCredentialStore(),
    pepper: 'test-pepper',
  );

  final first = await issuer.issueHumanityCredential(
    offerId: 'offer-1',
    holderDid: 'did:key:z6Mkholder1',
    holderProof: validHolderProof,
  );
  expect(first.isOk, isTrue);

  final second = await issuer.issueHumanityCredential(
    offerId: 'offer-2',
    holderDid: 'did:key:z6Mkholder2',
    holderProof: validHolderProofForSecondHolder,
  );
  expect(second.error, 'duplicate_active_credential');
});
```

- [ ] **Step 3: Run failing relay tests**

Run: `cd ansible_relay/server && dart test test/vc_issuer_test.dart test/vc_handler_test.dart`

Expected: fails because issuer modules and routes do not exist.

- [ ] **Step 4: Implement mock provider and issuer endpoints**

Implement offer, mock callback/session completion, issue, status, and presentation
verify endpoints from `docs/protocol/tris_aura_vc_wallet_spec_v0.1.md`.

- [ ] **Step 5: Run relay tests**

Run: `cd ansible_relay/server && dart test test/vc_issuer_test.dart test/vc_handler_test.dart`

Expected: issuer and handler tests pass.

## Task 5: Presentation And Reputation Integration

**Files:**

- Modify: `ansible_relay/server/lib/src/handlers/auth_handler.dart`
- Modify: `ansible_relay/server/lib/src/middleware.dart`
- Create: `ansible_relay/server/lib/src/vc/vp_verifier.dart`
- Test: `ansible_relay/server/test/vp_verifier_test.dart`
- Test: `ansible_relay/server/test/vc_reputation_test.dart`

- [ ] **Step 1: Write VP verifier tests**

```dart
test('rejects presentation with wrong audience', () {
  final result = VpVerifier.verify(
    presentation: validHumanityPresentationWithAudience('https://evil.example'),
    requestNonce: 'nonce-123',
    expectedAudience: 'https://relay.trisaura.io',
    statusResolver: (_) async => CredentialStatus.active,
  );

  expect(result.error, 'wrong_audience');
});

test('valid humanity presentation upgrades reputation tier', () async {
  final tier = await ReputationFromCredential.resolve(
    presentation: validHumanityPresentation(),
    requestNonce: 'nonce-123',
    audience: 'https://relay.trisaura.io',
  );

  expect(tier, 'verified_human');
});
```

- [ ] **Step 2: Run failing verifier tests**

Run: `cd ansible_relay/server && dart test test/vp_verifier_test.dart test/vc_reputation_test.dart`

Expected: fails because VP verifier and reputation mapping do not exist.

- [ ] **Step 3: Implement verifier and tier mapping**

Implement nonce, audience, holder, issuer, expiry, and status checks exactly as
listed in the protocol spec. Keep `unknown` status from unlocking privileged
actions.

- [ ] **Step 4: Run verifier tests**

Run: `cd ansible_relay/server && dart test test/vp_verifier_test.dart test/vc_reputation_test.dart`

Expected: presentation verification and tier mapping tests pass.

## Task 6: TW Provider Adapter Readiness

**Files:**

- Modify: `ansible_relay/server/lib/src/vc/tw_identity_provider.dart`
- Create: `ansible_relay/server/lib/src/vc/tw_identity_provider_contract.md`
- Test: `ansible_relay/server/test/tw_identity_provider_test.dart`

- [ ] **Step 1: Write adapter contract tests**

```dart
test('provider adapter rejects replayed callback state', () async {
  final provider = TwIdentityProvider.withMemoryState();
  await provider.startAuth(offerId: 'offer-1', state: 'state-1');

  final first = await provider.handleCallback({'state': 'state-1', 'assertion': 'signed'});
  expect(first.isVerified, isTrue);

  final replay = await provider.handleCallback({'state': 'state-1', 'assertion': 'signed'});
  expect(replay.error, 'callback_replay');
});
```

- [ ] **Step 2: Document required provider fields**

Write `tw_identity_provider_contract.md` with the approved callback fields,
signature validation rules, replay ID, subject derivation rule, and retention
requirements once partner documentation is available.

- [ ] **Step 3: Run provider tests**

Run: `cd ansible_relay/server && dart test test/tw_identity_provider_test.dart`

Expected: adapter rejects replay, state mismatch, expired sessions, and missing
provider proof.

## Verification Commands

Run these before marking the feature complete:

```bash
cd ansible_core/store && dart test
cd ansible_core/vc && dart test
cd ansible_relay/server && dart test
cd ansible_node/app && flutter test
```

Expected result: all tests pass. Any skipped external-provider tests must state
the missing sandbox or partner credential explicitly.
