# Taiwan Digital Identity VC Wallet Architecture

> Status: Draft for product, legal, and implementation review
> Owner areas: identity, wallet, relay, security
> Last updated: 2026-05-04

## 1. Purpose

Tris-Aura no longer treats ePassport NFC, MRZ, BAC, or PACE as the core human
verification path. The replacement direction is:

1. use Taiwan's natural person certificate ecosystem as the external identity
   assurance source;
2. issue Tris-Aura-owned Verifiable Credentials (VCs) after successful proofing;
3. store and present those credentials from the App, which therefore becomes a
   local Wallet as well as a forum client.

The product goal is not to publish a user's government identity. The product
goal is to let a DID holder prove a bounded statement such as "this account is
controlled by a verified human who completed Taiwan natural-person-certificate
identity proofing" while keeping raw legal identity outside public records.

## 1.1 Issuance Authority

`TrisAuraHumanityCredential` is issued only by a Tris-Aura-controlled Issuer
server. A user may hold the VC, store it in the App Wallet, and present it as a
VP, but the user must not self-issue this credential type.

Reason:

- Verified Human is a trust and Sybil-resistance credential.
- Its value comes from the Issuer verifying a TW FidO / MOICA-approved proofing
  result and applying duplicate-prevention policy.
- A self-issued humanity credential would only prove that the user made a claim
  about themself; it would not prove issuer-side identity assurance.

Self-issued credentials may exist later for profile-like claims, such as display
name, preferences, or personal metadata. They must not grant Verified Human,
rate-limit upgrades, gated community access, or issuer-backed trust labels.

## 2. Official Sources And Review Flags

Public official references checked on 2026-05-04:

- Taiwan 行動自然人憑證系統: https://fido.moi.gov.tw/
- 行動自然人憑證功能教學: https://fido.moi.gov.tw/pt/main/teaching
- 我的E政府 TW FidO article: https://www.gov.tw/News_Content_2_371636
- 我的E政府 行動自然人憑證 APP article: https://www.gov.tw/News_Content_13_762666

From public material, TW FidO / 行動自然人憑證 is positioned as a mobile natural
person certificate authentication service. Public teaching material describes
mobile-device binding, biometric/device verification, and NFC-related card/device
constraints. It also indicates mobile OS requirements and that NFC card binding
depends on supported natural person certificate IC cards.

The following statements are intentionally marked for review because they require
formal integration documents, partner approval, or a sandbox:

- REVIEW: Whether Tris-Aura can become an approved TW FidO relying party.
- REVIEW: Whether the provider returns a stable pseudonymous subject, a signed
  assertion, a certificate serial, or only an authentication result.
- REVIEW: Whether a third-party mobile app may initiate same-device identity
  proofing, or whether the flow must be web/QR based through an approved service.
- REVIEW: Whether a third-party service may use the proofing result to issue a
  private-sector VC.
- REVIEW: Whether derived duplicate-prevention commitments are regulated as
  personal data and what retention period is allowed.
- REVIEW: Whether App Store review treats the Wallet feature as normal credential
  storage or requires additional disclosures because it is identity-related.

## 3. Standards Baseline

The implementation should keep a narrow internal MVP while aligning naming and
semantics with public standards:

- W3C VC Data Model 2.0 for credential shape:
  https://www.w3.org/TR/vc-data-model-2.0/
- W3C DID Core for issuer and holder identifiers:
  https://www.w3.org/TR/did-1.0/
- OpenID4VCI 1.0 as the target issuance compatibility profile:
  https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html
- OpenID4VP 1.0 as the target presentation compatibility profile:
  https://openid.net/specs/openid-4-verifiable-presentations-1_0.html

Internal MVP APIs can be simpler than OID4VCI/OID4VP. They must still preserve
the same security properties: holder binding, nonce binding, audience binding,
issuer verification, expiry checks, and revocation checks.

## 4. Trust Model

| Role | Component | Responsibility |
|---|---|---|
| Holder | Tris-Aura App | Owns local DID keys, stores VCs, approves presentations |
| Identity provider | TW FidO / MOICA-approved flow | Authenticates the natural person |
| Credential issuer | Tris-Aura relay / issuer service | Issues Tris-Aura VCs after proofing |
| Verifier | Relay, AppView, private communities | Verifies VP and grants trust tier |
| DID registry | did:key initially, did:plc or did:web later | Resolves issuer and holder public keys |

Identity provider data must terminate at the issuer boundary. Public forum
records, sync envelopes, ActivityPub objects, and Tris-Aura posts must not embed
raw government identity attributes.

## 5. Privacy Boundary

Allowed default VC claims:

- `humanVerified: true`
- `assuranceLevel: "tw_natural_person_certificate"`
- `assuranceMethod: "tw_fido_or_moica"`
- `jurisdiction: "TW"`
- `verifiedAt`
- `expiresAt`

Prohibited default VC claims:

- national ID
- legal name
- birth date
- household registration address
- certificate serial number
- phone number
- email address
- raw provider assertion

Additional claims, such as age-over or residency, require a separate product and
legal review before implementation.

## 6. Duplicate-Prevention Commitment

The issuer needs a way to prevent one verified person from minting many active
high-trust credentials. The first production design should store a commitment,
not the raw government identifier:

```text
subject_commitment = HMAC-SHA256(
  issuer_secret_pepper,
  canonical_provider_subject || ":" || provider_assurance_context
)
```

Rules:

- The raw provider subject is never stored in application tables.
- The HMAC pepper lives in a secret manager or KMS, not source control.
- The commitment is used only for issuer-side duplicate prevention.
- The issued VC contains a random credential ID and does not expose the
  commitment.
- If future selective-disclosure or zero-knowledge tooling is adopted, replace
  this with a privacy-preserving nullifier.

If the provider does not return a stable provider subject, the integration must
stop at a weaker "verified session" level until a compliant uniqueness strategy
is approved.

## 7. Product Flows

### Flow A: Basic Account

The current app remains usable without government identity proofing:

1. User creates a local account.
2. App creates or imports a DID key.
3. Relay accepts normal signed operations.
4. Reputation tier is `basic`.

### Flow B: Upgrade To Verified Human

```text
App Wallet                  Tris-Aura Issuer              TW identity provider
    |                              |                              |
    |-- POST /api/v1/vc/offer ---->|                              |
    |   holder_did, types          |                              |
    |<-- offer + auth request -----|                              |
    |                              |                              |
    |-- open auth request -------->|-- redirect / QR / request -->|
    |                              |<-- assertion or result ------|
    |                              |                              |
    |-- POST /api/v1/vc/issue ---->|                              |
    |   holder_did, key proof      |                              |
    |<-- signed VC ----------------|                              |
    |                              |                              |
    | [encrypt and store locally]  |                              |
```

Acceptance criteria:

- Issuer verifies the identity-provider result before issuance.
- App proves control of the holder DID before receiving the VC.
- Duplicate active `TrisAuraHumanityCredential` issuance is rejected or returns
  the existing active credential state.
- App can recover Wallet display state after restart.
- No raw provider assertion is logged or stored in plaintext.

### Flow C: Present Credential

```text
Verifier                      App Wallet
   |                              |
   |-- presentation request ----->|
   |   nonce, audience, types     |
   |                              |
   | [user reviews and approves]  |
   |                              |
   |<-- verifiable presentation --|
   |   holder proof + VC          |
   |                              |
   | verify issuer, holder, nonce,
   | audience, expiry, status
```

Acceptance criteria:

- Presentation is bound to verifier nonce.
- Presentation is bound to verifier audience/domain.
- Wrong holder, wrong audience, replayed nonce, expired VC, revoked VC, and
  tampered VC all fail.
- User sees which credential and claim summary will be presented.

### Flow D: Refresh And Revocation

Initial policy:

- `TrisAuraHumanityCredential` lifetime: 90 days.
- Refresh window: starts 14 days before expiry.
- Online status check: required for trust-tier upgrades and gated communities.
- Offline display: allowed only for low-risk local UI badges.

## 8. Wallet Scope

The App needs a Wallet tab or screen group with:

- Wallet home: credential list, status, expiry, refresh action.
- Credential detail: issuer, type, issue date, expiry, claim summary.
- Add credential: starts TW identity proofing or mock proofing in dev.
- Presentation approval: verifier, requested credential type, requested claims,
  risk copy, approve/deny.
- Delete local credential: removes local encrypted payload and metadata.

Local storage:

| Table | Purpose |
|---|---|
| `wallet_credentials` | non-sensitive metadata and status |
| `wallet_credential_payloads` | encrypted VC payload bytes or keystore-wrapped blob reference |
| `wallet_presentations` | local-only audit trail without sensitive claims |
| `credential_status_cache` | cached revocation/suspension result |
| `issuer_trust_cache` | trusted issuer DID documents and key metadata |

App services:

- `WalletRepository`
- `CredentialStore`
- `VcIssuerClient`
- `VcPresentationService`
- `CredentialStatusClient`
- `IssuerTrustStore`

Core VC package responsibilities:

- parse VC JSON;
- sign and verify holder proofs;
- verify issuer proof;
- check expiry and credential type;
- build VP with nonce and audience binding.

## 9. Issuer Scope

Internal MVP endpoints:

| Endpoint | Purpose |
|---|---|
| `POST /api/v1/vc/offer` | Create issuance session and return auth URL/QR/mock token |
| `POST /api/v1/vc/tw/callback` | Receive and verify identity-provider result |
| `POST /api/v1/vc/issue` | Issue holder-bound VC after holder key proof |
| `GET /api/v1/vc/status/:credential_id` | Return active/revoked/suspended/expired status |
| `POST /api/v1/vc/presentations/verify` | Verify VP for server-side flows |

Issuer modules:

- `ansible_relay/server/lib/src/vc/vc_issuer.dart`
- `ansible_relay/server/lib/src/vc/vc_credential_store.dart`
- `ansible_relay/server/lib/src/vc/vc_status_registry.dart`
- `ansible_relay/server/lib/src/vc/tw_identity_provider.dart`
- `ansible_relay/server/lib/src/vc/subject_commitment.dart`
- `ansible_relay/server/lib/src/handlers/vc_handler.dart`

Issuer DID:

- MVP: `did:web:issuer.trisaura.io` once production hosting exists.
- Local dev: fixture issuer DID and test key stored only under test fixtures.
- DID document must publish assertion method key, issuer metadata endpoint, and
  key rotation policy.

## 10. Credential Types

### TrisAuraHumanityCredential

```json
{
  "@context": [
    "https://www.w3.org/ns/credentials/v2",
    "https://trisaura.io/contexts/humanity/v1"
  ],
  "id": "urn:uuid:2f4574e6-0ef3-4d87-bc24-5ab5168e6a7a",
  "type": ["VerifiableCredential", "TrisAuraHumanityCredential"],
  "issuer": "did:web:issuer.trisaura.io",
  "validFrom": "2026-05-04T00:00:00Z",
  "validUntil": "2026-08-02T00:00:00Z",
  "credentialSubject": {
    "id": "did:key:z6Mkholder",
    "humanVerified": true,
    "assuranceLevel": "tw_natural_person_certificate",
    "assuranceMethod": "tw_fido_or_moica",
    "jurisdiction": "TW"
  },
  "credentialStatus": {
    "id": "https://issuer.trisaura.io/status/humanity/2026-05#2f4574e6",
    "type": "TrisAuraStatusList2026",
    "statusPurpose": "revocation"
  }
}
```

### TrisAuraAgeOverCredential

Deferred until an approved source can provide age predicate data without
returning exact birth date to the App or public records.

### TrisAuraResidencyCredential

Deferred until a concrete community-governance need exists. Default posture is
not to issue residency credentials.

## 11. Development Phases

| Phase | Name | Exit criteria |
|---|---|---|
| P0 | Documentation and partner discovery | Integration questions, privacy review inputs, and protocol spec are ready |
| P1 | Local Wallet foundation | App can store, list, delete, and verify fixture VCs locally |
| P2 | Issuer MVP with mock TW assertion | Issuer can offer, issue, revoke, and verify VCs using test assertions |
| P3 | TW digital identity adapter | At least one approved sandbox or production proofing flow issues a VC |
| P4 | Presentation and reputation integration | Valid VP upgrades trust tier; invalid VP is rejected |
| P5 | OID4VCI/OID4VP compatibility | QR/metadata flows align with standards-oriented wallet/verifier fixtures |
| P6 | Production hardening | KMS, rotation, privacy, observability, and release checks are complete |

## 12. Engineering Guardrails

- Build P1 and P2 with deterministic fixtures before external integration.
- Do not block normal forum use when the identity provider is down.
- Keep mock proofing compiled out or feature-gated in production builds.
- Treat every identity-provider callback as replayable until nonce/state checks
  prove otherwise.
- Never put raw assertions, national identifiers, or provider subjects in logs.
- Do not make Wallet deletion imply issuer revocation unless the UI says so.
- Keep credential presentation explicit; no background presentation without user
  approval.
