# Taiwan Digital Identity VC Wallet Plan

> Status: Draft for implementation planning
> Owners: identity, wallet, relay, security
> Last updated: 2026-05-04

## 1. Purpose

Tris-Aura V2 no longer uses ePassport NFC / MRZ / BAC / PACE as the human
verification path. The replacement identity proofing path is Taiwan's natural
person certificate ecosystem, preferably through the mobile natural person
certificate service (TW FidO / 行動自然人憑證) when formal integration is
available.

The App must therefore become both:

1. a DID-based AT Protocol client for posts and sync, and
2. a wallet that stores, presents, refreshes, and revokes Tris-Aura-issued
   Verifiable Credentials (VCs).

Federation transition note: `did:plc` remains the current holder DID and
AT Protocol compatibility context for this wallet plan. It should not be read
as the only public identity path. Public Nostr identity is represented by
`did:nostr` / `npub`, while ActivityPub identity is a relay-domain Actor URL
such as `https://relay.trisaura.io/users/alice`.

The Relay/Issuer verifies a user through Taiwan digital identity, then issues a
privacy-preserving Tris-Aura VC bound to the user's holder DID. The App stores
that VC locally and presents it later for higher trust tiers, rate-limit
upgrades, or community access.

## 2. External Identity Sources

### Confirmed Public Facts

Taiwan's 行動自然人憑證 service provides mobile-device identity authentication
based on natural person certificates. The official service describes support for
biometric/device verification, digital services login, and integration by
government agencies or businesses. The official teaching page also states that
NFC card binding has card/device constraints: NFC binding is limited to TP07
natural person certificate IC cards, and mobile OS requirements include Android
9+ and iOS 15+.

Official references:

- 行動自然人憑證系統: https://fido.moi.gov.tw/
- 功能教學: https://fido.moi.gov.tw/pt/main/teaching
- 我的E政府 TW FidO page: https://www.gov.tw/News_Content_2_371636
- 行動自然人憑證 APP page: https://www.gov.tw/News_Content_13_762666

### Integration Assumptions To Confirm

The following items are not assumed as available until we obtain integration
documents or an official sandbox:

- Whether Tris-Aura can become an approved TW FidO relying party.
- Whether TW FidO returns a stable pseudonymous subject identifier, certificate
  serial, signed assertion, or only an authentication result.
- Whether digital signatures can be requested by third-party mobile apps, or
  only by approved web services / service providers.
- Whether the mobile App can use a same-device deep-link flow, a cross-device QR
  flow, or must use a web-based redirect through an approved relying party.
- Exact data minimization obligations, retention rules, audit log requirements,
  and whether the derived uniqueness key is regulated as personal data.

## 3. Target Trust Model

### Roles

| Role | Component | Responsibility |
|---|---|---|
| Holder | `ansible_node/app` | Owns DID keys, stores VCs, creates VPs |
| Identity Provider | TW FidO / MOICA | Authenticates the real person |
| Credential Issuer | `ansible_relay/phoenix` issuer module | Issues Tris-Aura VCs after proofing |
| Verifier | Relay, AppView, communities | Verifies VP and applies trust tier |
| Registry | DID / PLC / did:web | Resolves issuer and holder public keys |

### Identity Boundary

TW FidO / MOICA is used only for proofing. Tris-Aura does not publish the user's
government identity into AT Protocol records. The Tris-Aura VC should contain
minimal claims such as:

- `humanVerified: true`
- `assuranceLevel: "tw_natural_person_certificate"`
- `verifiedAt`
- `expiresAt`
- optional age/residency predicates only when needed

The VC must not contain raw national ID, birth date, legal name, address, phone,
email, certificate serial, or full MOICA assertion by default. Any product path
that needs a raw legal-identity claim requires explicit user disclosure or a
specific legal process; the default verified-human credential remains
minimal-disclosure.

### Uniqueness

To prevent one verified person from receiving many high-trust credentials, the
Issuer stores a uniqueness commitment:

```
subject_commitment = HMAC-SHA256(
  issuer_kms_pepper,
  canonical_provider_subject || ":" || provider_assurance_context
)
```

Rules:

- The raw provider subject is never stored.
- The HMAC pepper lives in KMS / secret manager, not source control.
- `subject_commitment` is used only by the Issuer for duplicate prevention.
- The issued VC contains a separate random credential ID and does not expose the
  commitment.
- If future selective disclosure or ZK tooling is adopted, replace this with a
  privacy-preserving nullifier.

## 4. Product Flows

### Flow A — Basic Account

Current V2 flow remains:

1. App creates local device key / passkey-style credential.
2. App creates or receives the current compatibility DID, today `did:plc`.
3. Relay anchors DID as `Basic`.
4. User can post with stronger rate limits than anonymous clients, but without
   verified-human privileges.

### Flow B — Upgrade To Verified Human

```
App / Wallet                 Tris-Aura Issuer              TW FidO / MOICA
    |                              |                              |
    |-- POST /api/v2/vc/offer ---->|                              |
    |   { holder_did, types }      |                              |
    |<-- credential_offer ---------|                              |
    |                              |                              |
    |-- open auth request -------->|-- auth redirect / QR ------->|
    |                              |<-- signed assertion / result-|
    |                              |                              |
    |<-- issuance session ready ---|                              |
    |-- POST /api/v2/vc/issue ---->|                              |
    |   { holder_did, key_proof }  |                              |
    |<-- VC -----------------------|                              |
    |                              |                              |
    | [store VC in wallet]         |                              |
```

Acceptance criteria:

- The Issuer verifies TW identity assurance before issuing.
- The App proves control of `holder_did`.
- The VC is holder-bound.
- Duplicate issuance for the same natural person is either rejected or returns
  the existing active credential status.
- The App can recover display state after restart without leaking sensitive
  claims into logs.

### Flow C — Present VC To Relay / Community

```
Verifier                    App Wallet
   |                            |
   |-- presentation request --->|
   |   { nonce, audience,       |
   |     accepted_types }       |
   |                            |
   | [user approves claims]     |
   |                            |
   |<-- verifiable presentation |
   |    { vp, holder_sig }      |
   |                            |
   | verify issuer + holder + expiry + revocation
```

Acceptance criteria:

- Presentation is bound to verifier challenge nonce.
- Presentation has an `audience` / domain binding.
- Expired, revoked, wrong-audience, wrong-holder, or tampered VCs fail.
- User sees which credential and claims will be presented.

### Flow D — Refresh / Revocation

VCs should be short-lived enough to limit stale trust but long-lived enough to
avoid frequent government authentication. Initial recommended policy:

- `TrisAuraHumanityCredential`: 90 days
- refresh window: 14 days before expiry
- revocation status check: online when presenting to Relay/AppView
- offline presentation: allowed only for low-risk UI badges, not rate-limit
  upgrades or gated communities

## 5. App Wallet Scope

### Wallet Storage

Add a local wallet store in SQLite plus encrypted payload storage:

| Data | Storage | Notes |
|---|---|---|
| VC metadata | SQLite | type, issuer DID, expiry, status, display label |
| VC payload | encrypted local storage | AES-GCM key wrapped by platform keystore |
| Holder keys | existing DID secure storage | never export private key |
| Presentation history | SQLite | local-only audit trail; no claim payloads |

Minimum tables:

- `wallet_credentials`
- `wallet_presentations`
- `credential_status_cache`
- `issuer_trust_cache`

### Wallet UI

Required screens:

- Wallet home: list credentials, status, expiry, refresh action.
- Credential detail: issuer, type, issued date, expiry, claims summary.
- Add credential: starts TW digital identity issuance.
- Presentation approval: requested verifier, requested claims, expiry, risk.
- Revocation / delete: remove local copy and optionally notify issuer.

### Wallet APIs

App services:

- `WalletRepository`
- `CredentialStore`
- `VcIssuerClient`
- `VcPresentationService`
- `CredentialStatusClient`
- `IssuerTrustStore`

Rust core:

- JSON canonicalization / JCS or Data Integrity canonicalization
- Ed25519 / Data Integrity proof signing
- VC / VP verification
- holder-binding proof generation

## 6. Relay / Issuer Scope

### New Relay Modules

- `AnsibleRelay.VcIssuer`
- `AnsibleRelay.VcCredentialStore`
- `AnsibleRelay.VcStatusRegistry`
- `AnsibleRelay.TwIdentityProvider`
- `AnsibleRelay.SubjectCommitment`
- `AnsibleRelay.Web.Controllers.VcIssuerController`

### New Endpoints

Initial internal API, before OID4VCI compatibility:

| Endpoint | Purpose |
|---|---|
| `POST /api/v2/vc/offer` | Create issuance session and return authorization URL / QR payload |
| `POST /api/v2/vc/tw/callback` | Receive/verify identity provider result |
| `POST /api/v2/vc/issue` | Issue holder-bound VC after key proof |
| `GET /api/v2/vc/status/:credential_id` | Return revocation / suspension / expiry status |
| `POST /api/v2/vc/presentations/verify` | Verify VP for server-side flows |

Compatibility target:

- OID4VCI for issuance once the internal flow is stable.
- OID4VP for verifier requests and presentation submission.

### Issuer DID

Use `did:web:issuer.trisaura.io` for the first production Issuer because it is
operationally simple and auditable. The DID document must publish:

- assertion method key for VC issuance
- service endpoint for issuer metadata
- rotated key history policy

Later, `did:plc` can be added if key rotation / delegation requirements align
better with the rest of the AT Protocol stack.

## 7. Credential Types

### TrisAuraHumanityCredential

Purpose: prove that a DID holder completed Taiwan natural person certificate
identity proofing, without exposing the legal identity.

Required claims:

```json
{
  "type": ["VerifiableCredential", "TrisAuraHumanityCredential"],
  "issuer": "did:web:issuer.trisaura.io",
  "credentialSubject": {
    "id": "did:plc:holder...",
    "humanVerified": true,
    "assuranceLevel": "tw_natural_person_certificate",
    "assuranceMethod": "tw_fido_or_moica",
    "jurisdiction": "TW"
  },
  "validFrom": "2026-05-04T00:00:00Z",
  "validUntil": "2026-08-02T00:00:00Z",
  "credentialStatus": {
    "type": "TrisAuraStatusList2026",
    "statusPurpose": "revocation",
    "statusListCredential": "https://issuer.trisaura.io/status/humanity/2026-05"
  }
}
```

Prohibited claims by default:

- national ID
- legal name
- birth date
- household registration address
- certificate serial number
- phone/email from the government flow

### TrisAuraAgeOverCredential

Optional later credential for communities that need age gates.

Claims:

- `ageOver: 18` or `ageOver: 20`
- no date of birth
- no exact age

This requires the upstream identity provider or an approved attribute source to
provide age information. Mark as blocked until source availability and legal
review are complete.

### TrisAuraResidencyCredential

Optional later credential for Taiwan-local governance.

Claims:

- `jurisdiction: "TW"`
- possibly city/county only if necessary and legally reviewed

Default posture: avoid this credential until a concrete product need exists.

## 8. Development Phases

### P0 — Documentation And Partner Discovery

Deliverables:

- This architecture plan.
- Protocol spec for credential issuance/presentation.
- Questions for TW FidO / MOICA integration.
- Data protection impact assessment draft.

Exit criteria:

- Chosen initial integration path: official TW FidO RP, MOICA web flow, manual
  review fallback, or staged mock.
- Confirmed whether same-device mobile flow is possible.
- Confirmed whether we can receive a stable pseudonymous subject or must derive
  one from signed certificate attributes.

### P1 — Local Wallet Foundation

Deliverables:

- Wallet tables and repository.
- Encrypted credential storage.
- Wallet UI skeleton.
- Import/delete/list credential flows using dev fixtures.
- VC parser and basic verification in Rust/Dart.

Tests:

- credentials persist across restart.
- encrypted payload is not stored as plaintext.
- expired credential is clearly marked.
- delete removes local payload and metadata.

### P2 — Tris-Aura Issuer MVP

Deliverables:

- Issuer DID (`did:web`) and signing key management.
- Internal `/api/v2/vc/offer`, `/issue`, `/status` endpoints.
- `TrisAuraHumanityCredential` issuance using mocked TW identity assertion.
- subject commitment duplicate protection.
- issuer-side audit logs without raw sensitive data.

Tests:

- cannot issue without holder DID proof.
- duplicate subject commitment cannot mint multiple active humanity VCs.
- issued VC verifies against issuer DID.
- revoked credential fails verification.

### P3 — TW Digital Identity Integration

Deliverables:

- Integration adapter for approved TW FidO / MOICA flow.
- Same-device or QR cross-device issuance UX.
- callback/assertion verification.
- production error mapping and retry rules.

Tests:

- callback replay rejected.
- state/nonce mismatch rejected.
- expired authorization session rejected.
- identity provider downtime keeps account usable but blocks new issuance.

Exit criteria:

- At least one real sandbox/production TW identity proofing flow completes and
  issues a wallet credential.

### P4 — Presentation And Reputation Integration

Deliverables:

- VP generation in App.
- Relay/AppView VP verification.
- Reputation Labeler consumes valid humanity VC and upgrades tier.
- presentation approval UI.

Tests:

- wrong audience rejected.
- wrong nonce rejected.
- wrong holder rejected.
- revoked/expired credential rejected.
- valid VC upgrades trust tier without exposing raw identity.

### P5 — OID4VCI / OID4VP Compatibility

Deliverables:

- Issuer metadata endpoint.
- Credential offer format compatible with OID4VCI.
- Presentation request/response compatible with OID4VP where practical.
- QR cross-device flow.

Exit criteria:

- A standards-oriented wallet/verifier test fixture can interoperate with our
  Issuer/Wallet for the supported credential format.

### P6 — Production Hardening

Deliverables:

- KMS-backed issuer keys and subject commitment pepper.
- issuer key rotation runbook.
- privacy review and retention policy.
- threat model and abuse response playbook.
- observability dashboards.
- backup / restore / revocation recovery drill.

Exit criteria:

- No dev fallback in production builds.
- Issuer private keys never appear in logs, DB, or app bundle.
- Personal data minimization has been reviewed.
- Security tests and release checklist are green.

## 9. Data Protection Requirements

Default rules:

- Do not store raw government identifiers.
- Do not log identity provider assertions.
- Do not include sensitive personal attributes in VCs unless strictly required.
- Use separate identifiers for:
  - holder DID
  - credential ID
  - subject uniqueness commitment
  - audit event ID
- Audit logs must record events, not claims.
- All credential issuance decisions must be reproducible from retained
  non-sensitive evidence and status codes.

## 10. Open Questions

- What exact TW FidO / MOICA relying-party protocol and sandbox are available?
- Can a non-government, non-financial app receive verified attributes, or only an
  authentication success?
- Does the provider assertion include a stable subject identifier suitable for
  duplicate prevention?
- What are the contractual restrictions on using TW FidO results to issue a
  private-sector VC?
- Does the App need to be a separate Wallet app, or can wallet functionality live
  inside the Tris-Aura app under app store rules and identity-provider terms?
- Which credential proof format should be the first production target:
  Data Integrity, JWT VC, or SD-JWT VC?
- What is the minimum disclosure set for "Verified Human" in the product UI?
