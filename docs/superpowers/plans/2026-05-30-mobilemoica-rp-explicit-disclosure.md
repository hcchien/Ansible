# MobileMoica RP Explicit Disclosure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an exception-gated MobileMoica / TW FidO relying-party issuance path that can open TW FidO through APP2APP, return to Elix, verify a provider result through an Issuer-side broker boundary, and issue a `TrisAuraHumanityCredential` without storing or issuing raw identity fields.

**Architecture:** Add a separate MobileMoica RP path instead of modifying the zkID path. Elix collects national ID only after explicit disclosure, calls new Issuer endpoints, opens the returned `mobilemoica://` deep link, polls status, and stores the returned VC. The Issuer owns service credentials and verification through a broker interface; production remains fail-closed until approval artifact IDs, MobileMoica service credentials, provider HTTP calls, trust anchors, PKCS#7 validation, and revocation checks are configured.

**Tech Stack:** Go 1.22 Issuer HTTP API, Go provider broker interfaces, Dart/Flutter Wallet UI and client methods, iOS URL scheme configuration, Android intent filters and package visibility, existing VC parser and wallet repository.

---

## Source Documents

- `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
- `docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`
- `docs/superpowers/specs/2026-05-30-mobilemoica-rp-explicit-disclosure-design.md`
- User-provided MobileMoica / TW FidO APP2APP integration notes. Treat service
  credentials, checksums, tickets, signed responses, and sample certificate
  material from that attachment as sensitive local input; do not commit them,
  print them in logs, or convert them into test fixtures.

## Constitution Review

This plan touches identity, credentials, Wallet, Issuer, and verification. It
implements the explicit-disclosure exception path from the design spec. The
feature must be disabled by default and must fail closed without legal, privacy,
security, and constitution approval artifact IDs.

The first implementation does not claim constitution compliance for ordinary
forum anti-abuse. It creates a narrowly gated path that requires explicit user
consent and keeps raw identity data out of VC payloads, logs, Relay payloads,
Forum Host payloads, AppView payloads, analytics, crash reports, and federation
payloads.

## Current Constraint

The provided APP2APP notes identify the MobileMoica endpoints and the
`mobilemoica://.../a2a/verifySign` scheme. The MobileMoica v2.9 interface
document provides the `sp_checksum` and `idp_checksum` construction, and the
Issuer provider now has checksum payload, generation, and verification helpers
plus `sp_ticket` parsing covered by synthetic test vectors. A real production
broker still cannot be enabled until provider HTTP calls, PKCS#7 validation,
approved trust anchors, and approved revocation checks are implemented.

## File Structure

Issuer:

- Create: `ansible_issuer/go/internal/provider/mobilemoica_rp.go`
- Create: `ansible_issuer/go/internal/provider/mobilemoica_rp_test.go`
- Create: `ansible_issuer/go/internal/api/mobilemoica.go`
- Create: `ansible_issuer/go/internal/api/mobilemoica_test.go`
- Modify: `ansible_issuer/go/internal/api/handler.go`
- Modify: `ansible_issuer/go/internal/vc/model.go`
- Modify: `ansible_issuer/go/internal/vc/issuer.go`
- Modify: `ansible_issuer/go/internal/vc/issuer_test.go`
- Modify: `ansible_issuer/go/cmd/server/main.go`
- Modify: `ansible_issuer/go/cmd/server/main_test.go`
- Modify: `docs/deployment/tw_provider_issuer_deployment.md`

Wallet:

- Modify: `ansible_node/app/lib/services/vc_issuer_client.dart`
- Create: `ansible_node/app/lib/screens/mobilemoica_rp_credential_screen.dart`
- Create: `ansible_node/app/test/mobilemoica_rp_credential_screen_test.dart`
- Modify: `ansible_node/app/test/vc_issuer_client_test.dart`
- Modify: `ansible_node/app/ios/Runner/Info.plist`
- Modify: `ansible_node/app/android/app/src/main/AndroidManifest.xml`

Docs:

- Modify: `docs/superpowers/specs/2026-05-30-mobilemoica-rp-explicit-disclosure-design.md`

## Task 1: Issuer VC Method For Explicit MobileMoica RP

- [ ] Write failing tests in `ansible_issuer/go/internal/vc/issuer_test.go` for
  `IssueMobileMoicaRP`, asserting:
  - VC type includes `TrisAuraHumanityCredential`;
  - `credentialSubject.assuranceMethod` is
    `mobilemoica_rp_explicit_disclosure`;
  - `credentialSubject.disclosureModel` is `explicit_rp`;
  - prohibited fields such as `nationalId`, `legalName`,
    `certificateSerialNumber`, `rawProviderAssertion`, `nationalIdHash`, and
    `providerSubject` are absent;
  - duplicate subject commitments are rejected.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/vc
  ```

  Expected: FAIL because `IssueMobileMoicaRP` and `disclosureModel` do not
  exist.

- [ ] Add `DisclosureModel string 'json:"disclosureModel,omitempty"'` to
  `CredentialSubject`.

- [ ] Add `IssueMobileMoicaRP(holderDID, subjectCommitment string)` to
  `Issuer`. It must call `store.CheckDuplicate(subjectCommitment)`, use
  `AssuranceLevel: "tw_natural_person_certificate"`,
  `AssuranceMethod: "mobilemoica_rp_explicit_disclosure"`,
  `Jurisdiction: "TW"`, and `DisclosureModel: "explicit_rp"`.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/vc
  ```

  Expected: PASS.

## Task 2: Provider MobileMoica RP Broker Boundary

- [ ] Create `ansible_issuer/go/internal/provider/mobilemoica_rp_test.go` with
  tests for:
  - approval config rejects missing legal/privacy/security/constitution IDs;
  - contract broker returns a `mobilemoica://` deep link and redacted offer
    result;
  - production broker returns an explicit unavailable error until provider HTTP
    calls, trust anchors, PKCS#7 validation, and revocation checks are
    implemented.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/provider
  ```

  Expected: FAIL because MobileMoica RP types do not exist.

- [ ] Create `mobilemoica_rp.go` with:
  - `MobileMoicaApprovalConfig`;
  - `ValidateMobileMoicaApprovalConfig`;
  - `MobileMoicaStartRequest`;
  - `MobileMoicaStartResult`;
  - `MobileMoicaVerificationResult`;
  - `MobileMoicaRPBroker` interface;
  - `ContractMobileMoicaRPBroker` for tests and local dev;
  - `ProductionMobileMoicaRPBroker` that returns
    `ErrMobileMoicaProductionUnavailable`.

- [ ] Contract broker behavior:
  - deep link scheme must be `mobilemoica`;
  - returned deep link must include a synthetic ticket but no national ID;
  - APP2APP `rtn_url` and `rtn_val` must be Base64URL encoded;
  - verification returns `ProviderSubject`, `ReplayID`, `AssuranceContext`,
    and `ExpiresAt`;
  - no response map contains raw national ID or signed response.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/provider
  ```

  Expected: PASS.

## Task 3: Issuer MobileMoica RP Endpoints

- [ ] Create `ansible_issuer/go/internal/api/mobilemoica_test.go` with tests
  for:
  - unconfigured endpoint returns `503 mobilemoica_rp_unconfigured`;
  - missing approval gate returns `503 mobilemoica_rp_unconfigured`;
  - start rejects invalid DID, missing consent fields, and invalid national ID;
  - start returns `offer_id`, `expires_at`, and `deep_link_url` using the
    `mobilemoica` scheme;
  - status transitions from `pending` to `verified`;
  - issue returns a VC with `assuranceMethod:
    mobilemoica_rp_explicit_disclosure`;
  - issue response does not contain national ID, signed response, legal name,
    certificate subject, service credential, or provider subject;
  - duplicate active commitment returns a conflict.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/api
  ```

  Expected: FAIL because endpoints and config do not exist.

- [ ] Add `MobileMoicaRPConfig` and `ConfigureMobileMoicaRP` to the API
  handler.

- [ ] Register:
  - `POST /api/v1/vc/mobilemoica/start`
  - `GET /api/v1/vc/mobilemoica/status/{offer_id}`
  - `POST /api/v1/vc/mobilemoica/issue`

- [ ] Implement start:
  - require configured store, broker, enabled flag, and approval config;
  - validate DID;
  - validate national ID with a local format regex;
  - require consent version and consent copy hash;
  - generate offer ID and state;
  - call broker start;
  - store auth session with no raw national ID;
  - return offer ID, expiry, and deep link.

- [ ] Implement status:
  - return verified if a verified session already exists;
  - find pending auth session by offer ID;
  - ask broker for result;
  - if pending, return pending;
  - if verified, consume auth state, compute
    `commitment.Compute(pepper, providerSubject,
    "mobilemoica_rp_explicit_v1:"+assuranceContext)`, store verified session,
    and return verified.

- [ ] Implement issue:
  - require holder DID and offer ID;
  - consume verified session;
  - reject holder mismatch;
  - call `issuer.IssueMobileMoicaRP`;
  - map duplicate credential errors to conflict.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/api
  ```

  Expected: PASS, unless this machine hits the known macOS dyld `LC_UUID`
  blocker. If blocked, run `go test -c -o /private/tmp/ansible_issuer_api.test
  ./internal/api`.

## Task 4: Server Config And Deployment Gate

- [ ] Add server tests in `ansible_issuer/go/cmd/server/main_test.go` for:
  - MobileMoica RP disabled by default;
  - enabled mode requires legal/privacy/security/constitution approval IDs;
  - contract mode creates config when all gates are present;
  - production mode fails closed with an explicit unavailable error.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./cmd/server
  ```

  Expected: FAIL because env builder support does not exist.

- [ ] Add env vars:
  - `MOBILEMOICA_RP_ENABLED`
  - `MOBILEMOICA_RP_ADAPTER_MODE`
  - `MOBILEMOICA_LEGAL_APPROVAL_ID`
  - `MOBILEMOICA_PRIVACY_APPROVAL_ID`
  - `MOBILEMOICA_SECURITY_APPROVAL_ID`
  - `MOBILEMOICA_CONSTITUTION_APPROVAL_ID`
  - `MOBILEMOICA_RETURN_URL`
  - `MOBILEMOICA_SESSION_TTL_SECONDS`

- [ ] Wire handler config only when `MOBILEMOICA_RP_ENABLED=true`.

- [ ] Update deployment docs with the fail-closed gate and note that production
  MobileMoica API calls remain blocked until production verification is
  implemented.

- [ ] Run:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./cmd/server
  ```

  Expected: PASS.

## Task 5: Wallet Client Methods

- [ ] Add Dart tests in `ansible_node/app/test/vc_issuer_client_test.dart`
  for:
  - start posts DID, national ID, consent version, consent copy hash, and
    locale to `/api/v1/vc/mobilemoica/start`;
  - status gets `/api/v1/vc/mobilemoica/status/{offerId}`;
  - issue posts DID and offer ID to `/api/v1/vc/mobilemoica/issue`;
  - no email is sent in MobileMoica RP requests.

- [ ] Run:

  ```bash
  cd ansible_node/app
  flutter test test/vc_issuer_client_test.dart
  ```

  Expected: FAIL because client methods do not exist.

- [ ] Add:
  - `MobileMoicaRPOffer`;
  - `MobileMoicaRPStatus`;
  - `startMobileMoicaRPFlow`;
  - `getMobileMoicaRPStatus`;
  - `issueMobileMoicaRPCredential`.

- [ ] Run:

  ```bash
  cd ansible_node/app
  flutter test test/vc_issuer_client_test.dart
  ```

  Expected: PASS.

## Task 6: Wallet Explicit Disclosure Screen

- [ ] Create `ansible_node/app/test/mobilemoica_rp_credential_screen_test.dart`
  with widget tests proving:
  - disclosure copy is visible before national ID entry;
  - start button is disabled until user accepts disclosure;
  - accepted flow posts national ID and consent metadata through the fake client;
  - the returned `mobilemoica://` deep link opens through the launcher;
  - pending then verified status issues and stores a VC;
  - security errors do not echo national ID or provider artifacts.

- [ ] Run:

  ```bash
  cd ansible_node/app
  flutter test test/mobilemoica_rp_credential_screen_test.dart
  ```

  Expected: FAIL because the screen does not exist.

- [ ] Create `mobilemoica_rp_credential_screen.dart`:
  - title `MobileMoica Verified Human`;
  - explicit non-zkID disclosure copy;
  - national ID text field appears only after consent checkbox is checked;
  - calls `startMobileMoicaRPFlow`;
  - launches `deepLinkUrl`;
  - polls status with the MobileMoica-recommended production interval of at
    least 4 seconds by default;
  - issues and stores the VC;
  - display name `MobileMoica Verified Human`;
  - all errors are redacted.
- [ ] Ensure the global app link handler treats
  `trisaura://mobilemoica/callback` as a MobileMoica foreground/resume signal,
  not as an invalid web-session approval link.

- [ ] Run:

  ```bash
  cd ansible_node/app
  flutter test test/mobilemoica_rp_credential_screen_test.dart
  ```

  Expected: PASS.

## Task 7: iOS And Android Deep Link Configuration

- [ ] Add static tests if existing project test style supports manifest/plist
  reads. Otherwise manually verify the files.

- [ ] Modify iOS `Info.plist`:
  - add Elix return URL scheme `trisaura`;
  - add `LSApplicationQueriesSchemes` entry `mobilemoica`.

- [ ] Modify Android `AndroidManifest.xml`:
  - add `trisaura://mobilemoica/callback` intent filter;
  - add package visibility query for `mobilemoica` scheme.

- [ ] Run:

  ```bash
  cd ansible_node/app
  flutter analyze lib/services/vc_issuer_client.dart lib/screens/mobilemoica_rp_credential_screen.dart
  ```

  Expected: PASS.

## Task 8: Verification

- [ ] Run issuer tests:

  ```bash
  cd ansible_issuer/go
  go test -count=1 ./internal/vc ./internal/provider ./cmd/server
  go test -c -o /private/tmp/ansible_issuer_api.test ./internal/api
  ```

- [ ] Run wallet tests:

  ```bash
  cd ansible_node/app
  flutter test test/vc_issuer_client_test.dart test/mobilemoica_rp_credential_screen_test.dart
  flutter analyze lib/services/vc_issuer_client.dart lib/screens/mobilemoica_rp_credential_screen.dart
  ```

- [ ] Run sensitive-value scans:

  ```bash
  rg -n "sp_service_id|aesKeyBase64|sp_checksum|signed_response|certificateSerialNumber|rawProviderAssertion" ansible_issuer/go ansible_node/app docs --glob '!docs/superpowers/plans/2026-05-30-mobilemoica-rp-explicit-disclosure.md'
  ```

  Expected: only documentation references to prohibited field names, no copied
  service credentials or sample signed responses.

## Acceptance Criteria

- The feature is disabled by default.
- Enabling the feature requires legal, privacy, security, and constitution
  approval artifact IDs.
- Elix can open a `mobilemoica://` URL and receive a `trisaura://mobilemoica`
  return URL.
- Contract mode completes start, status, issue, and wallet storage without raw
  identity in the VC.
- Production mode fails closed until provider HTTP calls, PKCS#7 validation,
  and approved trust-anchor / revocation validation are implemented.
- No service credential, national ID, signed response, legal name, certificate
  subject, certificate serial, provider subject, ticket, or duplicate
  commitment appears in VC payloads or normal logs.
