# Embedded ZKPassport Issuance Design

> Status: Approved direction; Beta until an independent security audit
> Date: 2026-07-23
> Scope: Elix Wallet, native passport reader, ZK prover, Issuer, and VC storage

## Goal

Complete the optional Passport NFC trust upgrade without sending raw passport
data to Elix infrastructure. The user scans the MRZ and ePassport chip inside
Elix, generates a ZKPassport proof on the phone, and presents that proof to the
Issuer. The Issuer verifies the proof and issues a minimal
`TrisAuraHumanityCredential`.

The experience must remain embedded in Elix. A WebView or redirect to the
ZKPassport application is not an embedded implementation.

## Upstream Baseline

The integration is based on Apache-2.0 ZKPassport sources pinned during design
review:

- `zkpassport/zkpassport-packages`
  `3cebce7eb54f056b511befafcdcd8d4429489bda`
- `zkpassport/mobile-app`
  `c52f5ef1c4c29ce3fd7e46c6dd25d172a1f1cb0e`
- `zkpassport/circuits`
  `d3a75acb8529e82c61be136a402553daec259257`
- circuit protocol version `0.20.0`

Production artifacts must be content-addressed and pinned. The app must not
silently accept a newly published circuit, verification key, SRS, registry
root, or native prover binary.

ZKPassport currently describes the software as experimental and externally
reviewed but not formally security-audited. Elix must label the method Beta
until the exact pinned integration receives an independent audit.

## Constitution Review

This feature touches identity, Wallet, Issuer, verification, storage, and
credentials, so the Tris-Aura Engineering Constitution applies in full.

1. The holder identity is the user's hardware-backed Elix DID. Passport NFC is
   an optional trust upgrade and never an account-creation gate.
2. MRZ, DG1, DG2, SOD, DSC, legal name, birth date, document number, face image,
   and BAC/PACE access keys remain ephemeral on the phone. They must not be sent
   to Elix, ZKPassport, Relay, AppView, analytics, crash reporting, or logs.
3. The Issuer learns only the minimum result: proof validity, requested
   nationality disclosure, holder/challenge binding, and an issuer-scoped
   unique identifier.
4. The issuer-scoped identifier is retained only for duplicate active binding.
   It must never be included in a VC, Relay record, presentation, or ordinary
   audit event.
5. The issued VC contains only `humanVerified`, `assuranceLevel`,
   `assuranceMethod`, and explicitly requested nationality.
6. Verification fails closed for unknown circuits, keys, roots, expired
   challenges, reused challenges, malformed proofs, unsupported documents, or
   unavailable registries.

This design is constitution-compliant if and only if those boundaries are
enforced by tests and production configuration. Sending raw passport material
to the Issuer is not an allowed fallback.

## Trust And Threat Model

The Issuer must not trust:

- an App boolean saying NFC or passive authentication succeeded;
- locally computed hashes not constrained by the proof;
- App Attest as evidence that a particular passport computation occurred;
- an unpinned circuit or verification key;
- a proof not bound to a fresh Issuer challenge and the holder DID.

The proof must establish:

- the DSC is chained to an accepted CSCA registry root;
- the SOD signature is valid for the DSC;
- committed DG data matches SOD hashes;
- the document is not expired at the challenged verification time;
- disclosed nationality is derived from committed document data;
- the unique identifier is derived under the Elix Issuer scope;
- the proof binds `holder_did`, challenge id, challenge nonce, issuer origin,
  and protocol version.

Active/chip authentication remains an additional signal where the document
supports it. Passive authentication is mandatory.

## Protocol

### 1. Challenge

`POST /api/v1/vc/passport/challenges`

Request:

```json
{"did":"did:plc:..."}
```

Response:

```json
{
  "challenge_id":"...",
  "nonce":"base64url-32-bytes",
  "issuer":"https://issuer-dev.elix.cool",
  "scope":"elix-passport-personhood-v1",
  "circuit_manifest_version":"0.20.0",
  "expires_at":"..."
}
```

Challenges are random, single-use, stored as hashes, expire after fifteen
minutes, and are atomically consumed only by a successful proof verification.
The bounded window accommodates foreground-only proving on current mobile
hardware; the DID, issuer, scope, nonce, and proof remain cryptographically
bound, and replay protection remains fail closed.

### 2. Local acquisition

The app scans MRZ with the camera, validates ICAO check digits, obtains explicit
user consent, then performs BAC/PACE and reads only the data groups required by
the selected proof. Sensitive buffers are not persisted and are zeroized where
the runtime permits.

### 3. Local proof

The embedded runtime generates ZKPassport base proofs and a disclosure/binding
proof. `custom_data` commits to a canonical digest of:

```text
elix-passport-v1
issuer_origin
holder_did
challenge_id
challenge_nonce
circuit_manifest_version
```

The query discloses nationality, proves a valid unexpired passport, requests an
issuer-scoped unique identifier, and discloses nothing else.

### 4. Verification and issuance

The app submits proof objects, the original query, query results, challenge id,
and holder DID. The Issuer verifier:

1. loads only pinned verification material;
2. verifies every proof and public-input relationship;
3. verifies the canonical holder/challenge binding;
4. rejects replay or expiry;
5. extracts the verified nationality and scoped identifier;
6. atomically enforces one active credential per scoped identifier;
7. issues the minimal VC and discards the proof payload after the bounded audit
   window.

## Embedded Runtime

Flutter calls a narrow platform plugin:

```text
prepare(version)
prove(passport_ephemeral_input, query, challenge_binding)
cancel()
clear()
```

On iOS the plugin uses Swoir/Swoirenberg's UltraHonk backend. Android uses the
corresponding Noir native backend. TypeScript input-generation behavior must be
ported or executed in an isolated bundled runtime with no network or storage
access. Network artifact retrieval belongs to the Flutter artifact manager,
which verifies pinned hashes before the prover sees a file.

No React Native UI, analytics, activity reporting, cloud prover, sanctions
service, FaceMatch, bridge, dashboard, or ZKPassport account dependency is
included in the initial Elix integration.

### On-demand SRS lifecycle

The approximately 128 MB public SRS is not bundled in the iOS or Android
application. It is fetched only when the user starts the one-time passport
proof flow:

1. the app clearly discloses the download size and shows progress;
2. the Flutter artifact manager downloads from the pinned HTTPS origin without
   attaching identity, passport, challenge, or analytics data;
3. it checks the exact byte length and pinned SHA-256 before giving the local
   path to the native prover;
4. it stores the verified file only in the application's temporary private
   directory; and
5. it deletes both complete and partial files after proof completion or
   failure. A later retry downloads and verifies a fresh copy.

Failure to download, verify, or remove the SRS must never cause passport data to
be sent to a cloud prover. An interrupted process may leave an OS-managed
temporary file; the next acquisition deletes stale complete and partial files
before downloading, and the operating system may independently purge the
temporary directory.

## Artifact Supply Chain

- A signed Elix manifest maps protocol versions to allowed circuit names,
  artifact SHA-256 values, verification-key hashes, SRS hash, and registry root.
- Dev and production use separate signed manifests.
- Updates require an app-supported protocol version and an Elix signature.
- Small, previously verified circuit artifacts may be cached with file
  protection. The SRS follows the stricter one-attempt lifecycle above.
- Circuit download failure must not fall back to the old Groth16 placeholder.
- The existing placeholder prover and `dev-*` proof acceptance must be removed
  from all release paths.

## UX

- Replace manual MRZ fields with `掃描護照資料頁`.
- Show a review screen containing only what will be disclosed:
  `真人驗證`, `國籍`, and `綁定這個 Elix 身分`.
- Explain that chip reading and proof generation can take time and should remain
  foregrounded.
- Show `Passport NFC · Beta` until the pinned implementation is audited.
- Separate errors into MRZ, NFC, unsupported document/circuit, proof generation,
  proof verification, duplicate binding, and Issuer availability.

## App Store Review

Review notes must explain the user-initiated identity trust upgrade, show the
MRZ-to-NFC sequence, state that passport data stays on-device, and provide a
video because reviewers may not have a compatible ePassport. The NFC usage
description, ISO 7816 AIDs, entitlement, and privacy disclosures must remain
consistent with actual behavior.

## Release Gate

The feature is not complete until:

- no release path calls the placeholder Groth16 prover;
- challenge replay, mutation, wrong-DID, wrong-origin, wrong-key, wrong-root,
  expired-document, and malformed-proof tests fail closed;
- a real supported passport succeeds end to end in dev;
- logs and crash reports are checked for forbidden fields;
- iOS and Android release artifacts use pinned prover and circuit material;
- Issuer readiness reports the exact enabled passport protocol version.
