# Engineering Constitution Compliance Review

> Date: 2026-05-24
> Scope reviewed: current specs, Wallet credential flows, Issuer VC issuance,
> Relay reputation mapping, Forum Host discovery, publication/federation guards,
> and key-storage hotspots.

## Result

The current specs and implementation are closer to the constitution after this
review, but the repo is not yet fully constitution-compliant. Two concrete
violations were fixed during the review. Two larger gaps remain as launch
blockers or follow-up implementation work.

## Fixed During Review

### Email OTP Is Not Verified Human

Issue:
The legacy Email OTP path was being treated as verified-human/personhood
assurance in Relay reputation mapping and in Wallet UI copy.

Fix:

- Relay now maps `EmailCredential` to `basic`, not `verified_human`.
- Go Issuer legacy `/api/v1/vc/issue` now issues `EmailCredential`, not
  `TrisAuraHumanityCredential`.
- Wallet stores Email OTP credentials as `EmailCredential` with display name
  `Email Verified`.
- Email OTP UI copy now says `Email 聯絡方式驗證`, not identity verification or
  Verified Human.

Constitution rules covered:

- Minimal-disclosure verification.
- Sybil resistance.
- Botnet/coordinated-manipulation resistance.

### Wallet Parser Now Rejects Passport And Personhood Claims

Issue:
The Dart `TrisAuraCredential` parser already rejected TW raw identity claims,
but did not reject passport raw fields or server-side personhood hashes if an
issuer accidentally included them in `credentialSubject`.

Fix:
The parser now rejects passport document fields, local passport IDs,
`national_id_hash`, `passport_number_hash`, raw MRZ, DG/SOD, and face image
claim names.

Constitution rules covered:

- Minimal-disclosure verification.
- Data autonomy.
- Sybil resistance.

### TW Mock Provider No Longer Falls Back To Raw Assertion As Subject

Issue:
The legacy in-memory provider test adapter used the raw `assertion` as a
fallback provider subject when `provider_subject` was missing.

Fix:
The adapter now rejects callbacks that have an assertion but no
`provider_subject`.

Constitution rules covered:

- Minimal-disclosure verification.
- Data autonomy.

## Reviewed As Compliant

### Passport NFC / TW Personhood Binding

The current Passport NFC and TW provider design follows the constitution:

- Passport NFC remains optional.
- Passport raw number stays local and ephemeral.
- Issuer receives only nationality, proof fields, and verifier-approved
  personhood hashes.
- Issuer blocks duplicate active bindings by `national_id_hash` or
  `passport_number_hash`.
- Issued humanity VC does not include raw passport fields, local passport UID,
  national ID hash, or passport number hash.

### Publication And Federation Visibility

The current publication path follows the constitution's local-first and
fail-closed rule:

- `PublicationIntent.canDistribute` rejects private content.
- The in-memory publication repository rejects private publication intents.
- Relay publication intent API rejects `private` visibility.
- Dev signatures are disabled by default and only allowed by explicit dev/test
  config.

### TW Provider Raw Data Retention Specs

Specs now align with the break-glass model:

- Provider subjects and assertions are issuer-boundary data only.
- Raw assertions are discarded by default.
- Any legally required retention path must be documented, scoped, encrypted,
  time-limited, audit-trailed, and user-visible when safe.

## Remaining Gaps

### Hardware-Backed Key Storage And Reduced-Trust Mode

Status: Partially implemented.

The mobile identity path now supports non-exportable P-256 keys in Secure
Enclave/Android Keystore, hardware-authorized device approval and revocation,
one-time recovery codes, delayed/vetoable recovery, and hardware-scoped private
board agreement keys. Legacy encrypted-key backup is explicitly reduced trust
and is not the default recovery authority for a hardware identity.

Some legacy DID, PLC, Nostr, desktop, and compatibility device-key paths still
persist or accept exportable key material. Those paths prevent a claim of full
compliance.

Required follow-up:

- Finish platform-backed signing and attestation for every supported desktop
  and protocol-specific key path.
- Remove the legacy enrolled-device signature fallback after existing clients
  have migrated to hardware identity authorization.
- Prevent raw private key export from the remaining first-party self-custody
  paths and retain explicit reduced-trust labeling where hardware is absent.

Constitution rules affected:

- Identity autonomy.
- Data autonomy.

### External Host Compliance Level

Status: Partially implemented.

Forum Host and Relay discovery now expose constitution compliance level, and
Relay discovery defaults unknown/missing external values to `unknown`. The app
first-run discovery surface parses and displays compliance labels before a user
relies on starter host/board results.

The remaining gap is local persistence and policy use: local `ForumHost` /
`RemoteNode` storage does not yet persist compliance level, and ranking, sync,
recommendation, and trust policy do not yet consume it.

Required follow-up:

- Add `constitution_compliance` to local host records.
- Default unknown external hosts to `unknown`.
- Let first-party ranking, trust, recommendation, or sync policy read the
  compliance level before relying on external host behavior.

Constitution rules affected:

- Scope and compliance.
- Healthy community discussion.
- Minimal global rules with transparent host governance.

## Verification Commands

- `go test -count=1 ./internal/vc`
- `go test -count=1 ./internal/provider`
- `go test -c -o /private/tmp/ansible_issuer_api.test ./internal/api`
- `mix test test/reputation_controller_test.exs`
- `flutter analyze lib/src/tris_aura_credential.dart test/tris_aura_credential_test.dart`
- `flutter test test/tris_aura_credential_test.dart`
- `flutter analyze lib/screens/credential_issuance_wizard.dart lib/screens/add_credential_screen.dart test/credential_issuance_wizard_test.dart test/add_credential_screen_test.dart test/vc_issuer_client_test.dart`
- `flutter test test/credential_issuance_wizard_test.dart test/add_credential_screen_test.dart test/vc_issuer_client_test.dart`

Known local blocker:

- `go test -count=1 ./internal/api` still aborts on this machine with macOS
  dyld `missing LC_UUID load command`. The package compiles with `go test -c`.
