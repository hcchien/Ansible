# Passport Wallet Credential Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Passport NFC as an optional Wallet credential method while keeping raw passport/ID values local-only and enforcing one active server-side binding per verifier-produced `national_id_hash` or `passport_number_hash`.

**Architecture:** First unify app Wallet storage paths on the W3C VC v2.0 `TrisAuraCredential` parser so Go issuer output can be stored correctly. Then add local passport extension metadata, a secure local HMAC id service, a proof-backed passport issuer/client endpoint, and a Passport NFC panel in the shared credential wizard. The Issuer must use a configured passport verifier and reject duplicate active national ID or passport number commitments.

**Tech Stack:** Flutter/Dart app, Drift wallet repository, `flutter_secure_storage`, Go issuer API, W3C VC Data Model v2.0 JSON shape, existing `NfcPassportReader` interface.

---

### Task 1: Store Issuer V2 Credentials Through `TrisAuraCredential`

**Files:**
- Modify: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`
- Modify: `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Test: `ansible_node/app/test/tw_provider_credential_screen_test.dart`
- Test: `ansible_node/app/test/credential_issuance_wizard_test.dart`

- [ ] **Step 1: Write failing tests**

Add test fixtures that use `validFrom` and `validUntil`, not `issuanceDate` and `expirationDate`, then assert TW provider and email storage can persist them:

```dart
final _v2CredentialJson = <String, dynamic>{
  '@context': [
    'https://www.w3.org/ns/credentials/v2',
    'https://trisaura.io/contexts/humanity/v1',
  ],
  'id': 'urn:uuid:v2-credential',
  'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
  'issuer': 'did:web:issuer.trisaura.io',
  'validFrom': '2026-05-10T00:00:00Z',
  'validUntil': '2026-08-08T00:00:00Z',
  'credentialSubject': {
    'id': 'did:plc:abcdefghijklmnop',
    'humanVerified': true,
    'assuranceMethod': 'tw_fido_or_moica',
  },
  'proof': {'proofValue': 'issuer-proof'},
};
```

Expected failures before implementation: `type 'Null' is not a subtype of type 'String'` or a parser error from legacy `VerifiableCredential.fromJson`.

- [ ] **Step 2: Run failing tests**

Run:

```bash
cd ansible_node/app
flutter test test/tw_provider_credential_screen_test.dart test/credential_issuance_wizard_test.dart
```

Expected: the new v2 credential tests fail before the parser change.

- [ ] **Step 3: Implement shared v2 storage helper**

Add a local helper in each touched screen or a small shared helper in `credential_issuance_wizard.dart` that parses with `TrisAuraCredential.fromJson`, seals the original JSON payload, and stores `WalletCredential` metadata from `validFrom` / `validUntil`.

The helper must set:

```dart
credentialType: credential.hasType('TrisAuraHumanityCredential')
    ? 'TrisAuraHumanityCredential'
    : credential.types.last,
validFrom: credential.validFrom,
validUntil: credential.validUntil,
```

- [ ] **Step 4: Run tests**

Run the same Flutter test command. Expected: TW provider and credential wizard tests pass.

### Task 2: Add Passport Local Unique ID Service

**Files:**
- Create: `ansible_node/app/lib/services/passport_local_id_service.dart`
- Test: `ansible_node/app/test/passport_local_id_service_test.dart`

- [ ] **Step 1: Write failing tests**

Tests must verify same inputs produce the same id, different document numbers or secrets produce different ids, and the raw document number does not appear in the output.

Expected API:

```dart
final service = PassportLocalIdService.fixedSecret('wallet-secret');
final id = service.derive(
  nationality: 'TWN',
  documentNumber: '300012345',
);
```

- [ ] **Step 2: Run failing test**

Run:

```bash
cd ansible_node/app
flutter test test/passport_local_id_service_test.dart
```

Expected: compile failure because `PassportLocalIdService` does not exist.

- [ ] **Step 3: Implement service**

Use `Hmac(sha256, utf8.encode(secret))` over:

```text
passport:v1|<uppercased nationality>|<documentNumber>
```

Return a string prefixed with `passport-local-v1-` and a hex digest. Production constructor reads or creates a random local secret in `FlutterSecureStorage`; the fixed-secret constructor is test-only.

- [ ] **Step 4: Run test**

Run the same Flutter test. Expected: all tests pass.

### Task 3: Add Wallet Passport Extension Storage

**Files:**
- Create: `ansible_core/store/lib/src/entities/passport_wallet_extension.dart`
- Create: `ansible_core/store/lib/src/schema/passport_wallet_extensions.dart`
- Modify: `ansible_core/store/lib/src/db/app_database.dart`
- Modify: `ansible_core/store/lib/src/repositories/wallet_repository.dart`
- Modify: `ansible_core/store/lib/src/repositories/in_memory/in_memory_wallet_repository.dart`
- Modify: `ansible_core/store/lib/src/repositories/drift/drift_wallet_repository.dart`
- Regenerate: `ansible_core/store/lib/src/db/app_database.g.dart`
- Test: `ansible_node/app/test/passport_wallet_extension_repository_test.dart`

- [ ] **Step 1: Write failing repository tests**

Use `InMemoryWalletRepository` first. Tests should save:

```dart
PassportWalletExtension(
  credentialId: 'urn:uuid:passport',
  passportLocalUniqueId: 'passport-local-v1-abc',
  nationalIdHash: 'national-id-hash-abc',
  passportNumberHash: 'passport-number-hash-abc',
  nationality: 'TWN',
  assuranceMethod: 'passport_nfc',
  verifiedAt: DateTime.utc(2026, 5, 24),
)
```

Assert lookup by local unique id returns the extension and that the entity has no `documentNumber` field.

- [ ] **Step 2: Run failing test**

Run:

```bash
cd ansible_node/app
flutter test test/passport_wallet_extension_repository_test.dart
```

Expected: compile failure because the extension entity and repository methods do not exist.

- [ ] **Step 3: Implement entity and repository API**

Add methods to `WalletRepository`:

```dart
Future<void> savePassportExtension(PassportWalletExtension extension);
Future<PassportWalletExtension?> getPassportExtensionByLocalUniqueId(
  String passportLocalUniqueId,
);
Future<PassportWalletExtension?> getPassportExtensionForCredential(
  String credentialId,
);
```

Update in-memory and Drift repositories.

- [ ] **Step 4: Update Drift schema**

Add `PassportWalletExtensions` to `AppDatabase`, increment schema version, add migration create-table block, then regenerate:

```bash
cd ansible_core/store
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 5: Run tests**

Run the repository test and any existing wallet repository tests. Expected: pass.

### Task 4: Add Passport Issuer API and Client

**Files:**
- Modify: `ansible_issuer/go/internal/vc/model.go`
- Modify: `ansible_issuer/go/internal/vc/issuer.go`
- Modify: `ansible_issuer/go/internal/api/handler.go`
- Test: `ansible_issuer/go/internal/vc/issuer_test.go`
- Test: `ansible_issuer/go/internal/api/handler_test.go`
- Modify: `ansible_node/app/lib/services/vc_issuer_client.dart`
- Test: `ansible_node/app/test/vc_issuer_client_test.dart`

- [ ] **Step 1: Write failing Go issuer/API tests**

Add tests that `IssuePassport(holderDID, "TWN", "national-id-hash-abc", "passport-number-hash-abc")` returns a credential whose subject includes `nationality: "TWN"` and `assuranceMethod: "passport_nfc"` and does not contain passport number, local unique id, national ID hash, or passport number hash. Add API tests for `POST /api/v1/vc/passport/issue`, unconfigured verifier rejection, duplicate national ID rejection, and duplicate passport number rejection.

- [ ] **Step 2: Run failing Go tests**

Run:

```bash
cd ansible_issuer/go
go test ./internal/vc
go test ./internal/api
```

Expected: compile failure or 404 until endpoint exists.

- [ ] **Step 3: Implement Go issuer/API**

Add a passport issuance method that indexes active verifier-produced personhood hashes. The endpoint accepts JSON:

```json
{
  "did":"did:plc:abcdefghijklmnop",
  "nationality":"TWN",
  "national_id_hash":"national-id-hash-abc",
  "passport_number_hash":"passport-number-hash-abc",
  "zkp_proof":"proof-abc",
  "zkp_circuit_version":"passport_v1_groth16_bn254",
  "verification_key_hash":"sha256:vk-hash"
}
```

It rejects missing DID, invalid DID, missing nationality, invalid nationality, invalid personhood hashes, missing proof fields, unconfigured verifier, invalid proof, and duplicate active national ID or passport number hash. It must not accept `verified: true`.

- [ ] **Step 4: Write failing Dart client test**

Assert `VcIssuerClient.issuePassportCredential(...)` posts only:

```json
{
  "did":"did:plc:abcdefghijklmnop",
  "nationality":"TWN",
  "national_id_hash":"national-id-hash-abc",
  "passport_number_hash":"passport-number-hash-abc",
  "zkp_proof":"proof-abc",
  "zkp_circuit_version":"passport_v1_groth16_bn254",
  "verification_key_hash":"sha256:vk-hash"
}
```

and does not include `verified`, raw document number, or passport local unique id.

- [ ] **Step 5: Implement Dart client method and run tests**

Run:

```bash
cd ansible_node/app
flutter test test/vc_issuer_client_test.dart
```

Expected: pass.

### Task 5: Add Passport NFC Panel to Credential Wizard

**Files:**
- Modify: `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Test: `ansible_node/app/test/credential_issuance_wizard_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add tests that the wizard shows a `Passport NFC` method, blocks local duplicates before calling Issuer, and stores a passport credential plus extension on success using a fake `NfcPassportReader`.

- [ ] **Step 2: Run failing tests**

Run:

```bash
cd ansible_node/app
flutter test test/credential_issuance_wizard_test.dart
```

Expected: missing method / UI failures.

- [ ] **Step 3: Implement panel**

Add `CredentialIssuanceFlow.passportNfc` and `PassportNfcCredentialPanel`. Inject `NfcPassportReader`, `PassportLocalIdService`, `VcIssuerClient`, and `WalletRepository` for testability. The panel must:

1. scan passport;
2. derive local id;
3. check duplicate local id;
4. generate a ZKP/nullifier from the passport secret;
5. call issuer with DID, nationality, national ID hash, passport number hash, and proof fields;
6. parse issuer response through `TrisAuraCredential`;
7. save encrypted payload, wallet metadata, and passport extension.

- [ ] **Step 4: Run widget tests**

Run the credential wizard tests. Expected: pass.

### Task 6: Verification

**Files:**
- No new files.

- [ ] **Step 1: Run targeted Flutter tests**

```bash
cd ansible_node/app
flutter test \
  test/passport_local_id_service_test.dart \
  test/passport_wallet_extension_repository_test.dart \
  test/vc_issuer_client_test.dart \
  test/credential_issuance_wizard_test.dart \
  test/tw_provider_credential_screen_test.dart
```

- [ ] **Step 2: Run targeted Go tests**

```bash
cd ansible_issuer/go
go test ./internal/vc
go test ./internal/api
```

If `internal/api` still aborts locally with `missing LC_UUID load command`, report it as an environment blocker and include the exact output.

- [ ] **Step 3: Check privacy constraints**

Run:

```bash
rg -n "documentNumber|passportLocalUniqueId|national_id_hash|passport_number_hash|passport_uid|verified: true|provider_subject|rawProviderAssertion" \
  ansible_node/app/lib ansible_issuer/go/internal
```

Confirm that `documentNumber` is only used before local id / proof derivation, issuer/client payload code does not send `passportLocalUniqueId` or raw passport number, personhood hashes are not placed in VC claims, and passport issuance no longer uses a client-supplied `verified: true` flag.
