# Embedded ZKPassport Issuance Implementation Plan

> Status: In progress
> Date: 2026-07-23

## Constitution Review

The constitution applies because this work changes identity verification,
Wallet storage, Issuer behavior, credentials, and anti-Sybil bindings. The
implementation must follow
`2026-07-23-embedded-zkpassport-issuance-design.md`; especially, raw passport
material never leaves the phone and no mock or client assertion may authorize
production issuance.

## Upstream Pins

- packages: `3cebce7eb54f056b511befafcdcd8d4429489bda`
- mobile: `c52f5ef1c4c29ce3fd7e46c6dd25d172a1f1cb0e`
- circuits: `d3a75acb8529e82c61be136a402553daec259257`
- protocol: `0.20.0`

## Phase 1 — Protocol And Fail-Closed Migration

- [x] Add durable single-use passport challenge storage.
- [x] Add challenge create endpoint and validation tests.
- [ ] Replace the legacy proof envelope with versioned ZKPassport proof/query
      objects and canonical holder binding.
- [x] Remove release fallback to `dev-*` proofs and the unconstrained Groth16
      circuit.
- [ ] Extend `/readyz` with passport verifier protocol/readiness.

## Phase 2 — Embedded Prover Platform

- [ ] Create a Flutter-facing `EmbeddedPassportProver` interface.
- [x] Add iOS Swoir/Swoirenberg native plugin pinned to an exact revision.
- [ ] Add Android Noir native plugin pinned to an exact revision.
- [ ] Port the minimal ZKPassport passport model and circuit input generators.
- [ ] Exclude bridge, dashboard, analytics, cloud prover, sanctions, and
      FaceMatch code.
- [ ] Add cancellation, memory-pressure handling, protected cache, and sensitive
      buffer cleanup.

## Phase 3 — Artifact And Registry Supply Chain

- [ ] Create signed dev/prod Elix artifact manifests.
- [ ] Implement content-addressed circuit, vkey, SRS, and registry downloads.
- [ ] Verify every artifact before use and reject unknown versions.
- [ ] Add rollback-safe cache and manifest rotation.
- [ ] Document upstream update and license/NOTICE procedure.

## Phase 4 — MRZ And NFC

- [x] Add camera MRZ scanning on iOS.
- [ ] Add camera MRZ scanning on Android.
- [ ] Validate TD1/TD2/TD3 ICAO check digits before NFC.
- [ ] Extend native NFC output to the ephemeral ZKPassport passport model.
- [ ] Preserve current BAC/PACE, passive-authentication, and chip-authentication
      checks without persisting raw data.
- [ ] Remove manual MRZ entry from release UI; keep explicit test injection only.

## Phase 5 — Issuer Verifier

- [x] Add the pinned ZKPassport verifier as an isolated Issuer component.
- [ ] Verify all base/disclosure proofs and public-input relationships.
- [ ] Verify holder DID, challenge, origin, scope, time, and protocol binding.
- [x] Atomically consume challenges and enforce scoped-identifier uniqueness.
- [ ] Keep proof payloads out of normal logs and apply bounded retention.
- [ ] Issue only the minimal passport humanity VC.

## Phase 6 — Integration And Security Verification

- [ ] Real passport dev smoke test.
- [ ] Mutation/replay/wrong-DID/wrong-origin/wrong-key/wrong-root tests.
- [ ] Expired/revoked/unsupported passport and interrupted NFC tests.
- [ ] Forbidden-field scan across storage, HTTP bodies, logs, and crash events.
- [ ] Flutter, Go, Rust/native, iOS archive, and Android bundle CI.
- [ ] Independent review of the exact pinned cryptographic integration.

## Phase 7 — Release

- [ ] Deploy dev Issuer verifier and verify readiness/version.
- [ ] Upload TestFlight and Google Play internal-test builds with Beta label.
- [ ] Prepare App Review NFC demonstration video and review notes.
- [ ] Promote to production only after the release gate in the design passes.
