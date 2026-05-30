# Tris-Aura VC Wallet Protocol Spec v0.1

> Status: Draft
> Related architecture: [`../architecture/tw_digital_identity_vc_wallet.md`](../architecture/tw_digital_identity_vc_wallet.md)
> Last updated: 2026-05-04

## 1. Scope

This spec defines the internal MVP protocol for:

- requesting a Tris-Aura credential offer;
- completing Taiwan digital identity proofing through an approved provider flow;
- issuing a holder-bound VC from the Tris-Aura Issuer server;
- storing and presenting that VC from the App Wallet;
- verifying presentations for trust-tier upgrades.

The MVP protocol is intentionally smaller than OID4VCI/OID4VP, but its fields
are named so the system can later add standards-compatible metadata, offers, and
presentation requests.

## 1.1 Issuer Boundary

The App never self-issues `TrisAuraHumanityCredential`. The App is the holder and
wallet. The Tris-Aura Issuer server is the only component allowed to issue this
credential type.

The App may:

- request a credential offer;
- open or continue the approved Taiwan digital identity proofing flow;
- prove control of the holder DID;
- store the issued VC;
- present the VC as a VP.

The Issuer server must:

- verify the TW FidO / MOICA-approved result;
- enforce nonce, state, expiry, and replay checks;
- compute issuer-side subject commitments for duplicate prevention;
- verify holder DID proof before issuance;
- sign the VC with an issuer assertion key;
- publish status/revocation information.

Self-issued VCs are out of scope for Verified Human. They may be introduced later
for profile claims, but verifiers must not treat them as identity assurance.

## 2. Credential Offer

### Request

`POST /api/v1/vc/offer`

```json
{
  "holder_did": "did:key:z6Mkholder",
  "requested_types": ["TrisAuraHumanityCredential"],
  "client_nonce": "base64url-random-32-bytes"
}
```

### Response

```json
{
  "offer_id": "vc-offer-01HX8QGJ5A2Y8V5J61D6GZ",
  "issuer": "did:web:issuer.trisaura.io",
  "expires_at": "2026-05-04T10:15:00Z",
  "auth_request": {
    "mode": "external",
    "url": "https://issuer.trisaura.io/tw/auth/start?offer_id=vc-offer-01HX8QGJ5A2Y8V5J61D6GZ",
    "qr_payload": "trisaura-vc-offer://vc-offer-01HX8QGJ5A2Y8V5J61D6GZ"
  }
}
```

Dev fixture response may use:

```json
{
  "auth_request": {
    "mode": "mock",
    "mock_assertion_token": "test-only-token"
  }
}
```

Mock mode must be disabled in production configuration.

## 3. Provider Callback

`POST /api/v1/vc/tw/callback`

The exact callback body depends on the approved TW FidO/MOICA integration
contract. The issuer normalizes it into:

```json
{
  "offer_id": "vc-offer-01HX8QGJ5A2Y8V5J61D6GZ",
  "provider": "tw_fido_or_moica",
  "assurance_context": "tw_natural_person_certificate",
  "provider_subject": "provider-stable-subject-or-approved-derivation",
  "assertion_verified_at": "2026-05-04T10:11:00Z",
  "provider_assertion_id": "provider-replay-id"
}
```

Storage rule:

- Store `provider_assertion_id` only if needed for replay detection.
- Store `subject_commitment`.
- Do not store `provider_subject`.
- Do not store raw assertion payloads by default. Any legally required
  retention path must be a documented break-glass exception with explicit
  purpose, time limit, encrypted storage, no application logs, and user-visible
  notice when safe.

## 4. Issue Credential

### Request

`POST /api/v1/vc/issue`

```json
{
  "offer_id": "vc-offer-01HX8QGJ5A2Y8V5J61D6GZ",
  "holder_did": "did:key:z6Mkholder",
  "holder_proof": {
    "type": "DataIntegrityProof",
    "cryptosuite": "eddsa-jcs-2022",
    "challenge": "issuer-session-nonce",
    "proofValue": "zBase58BtcMultibaseSignature"
  }
}
```

### Response

```json
{
  "credential": {
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
    },
    "proof": {
      "type": "DataIntegrityProof",
      "cryptosuite": "eddsa-jcs-2022",
      "verificationMethod": "did:web:issuer.trisaura.io#key-2026-05",
      "created": "2026-05-04T10:12:00Z",
      "proofPurpose": "assertionMethod",
      "proofValue": "zBase58BtcMultibaseSignature"
    }
  }
}
```

Error codes:

| Status | Error | Meaning |
|---|---|---|
| 400 | `unsupported_credential_type` | Client requested an unsupported VC type |
| 401 | `invalid_holder_proof` | Holder DID proof failed |
| 409 | `duplicate_active_credential` | Same subject commitment already has an active humanity VC |
| 410 | `offer_expired` | Offer expired before issuance |
| 422 | `identity_not_verified` | Provider proofing has not completed |

## 5. Wallet Storage Contract

`wallet_credentials`:

```text
credential_id       text primary key
issuer_did          text not null
holder_did          text not null
credential_type     text not null
status              text not null  -- active | expired | revoked | suspended | deleted
valid_from          datetime not null
valid_until         datetime not null
display_name        text not null
created_at          datetime not null
updated_at          datetime not null
```

`wallet_credential_payloads`:

```text
credential_id       text primary key
encrypted_payload   blob/text not null
encryption_version  text not null
created_at          datetime not null
```

`wallet_presentations`:

```text
presentation_id     text primary key
credential_id       text not null
verifier_audience   text not null
nonce_hash          text not null
result              text not null  -- approved | denied | failed
created_at          datetime not null
```

The presentation table stores nonce hashes and result metadata, not raw claim
payloads.

## 6. Presentation Request

```json
{
  "request_id": "vp-request-01HX8QYJBT7KXW",
  "audience": "https://relay.trisaura.io",
  "nonce": "base64url-random-32-bytes",
  "accepted_types": ["TrisAuraHumanityCredential"],
  "purpose": "Upgrade reputation tier to Verified Human",
  "expires_at": "2026-05-04T10:20:00Z"
}
```

## 7. Presentation Response

```json
{
  "verifiable_presentation": {
    "@context": ["https://www.w3.org/ns/credentials/v2"],
    "type": ["VerifiablePresentation"],
    "holder": "did:key:z6Mkholder",
    "verifiableCredential": [
      {
        "id": "urn:uuid:2f4574e6-0ef3-4d87-bc24-5ab5168e6a7a",
        "type": ["VerifiableCredential", "TrisAuraHumanityCredential"]
      }
    ],
    "proof": {
      "type": "DataIntegrityProof",
      "cryptosuite": "eddsa-jcs-2022",
      "verificationMethod": "did:key:z6Mkholder#key-1",
      "created": "2026-05-04T10:18:00Z",
      "proofPurpose": "authentication",
      "challenge": "base64url-random-32-bytes",
      "domain": "https://relay.trisaura.io",
      "proofValue": "zBase58BtcMultibaseSignature"
    }
  }
}
```

Verifier checks:

1. `holder` matches `credentialSubject.id`.
2. Holder proof verifies against holder DID key.
3. Issuer proof verifies against trusted issuer DID key.
4. `challenge` equals request nonce.
5. `domain` equals request audience.
6. Credential type is accepted.
7. `validFrom <= now < validUntil`.
8. Credential status is active.

## Constitution Review

- The proof-suite change does not add any new identity claim or storage path.
- VC and VP subjects remain holder DIDs; raw legal identity and personhood
  commitments remain excluded from proof values, credential subjects, relay
  payloads, federation payloads, and logs.
- The change improves credential verifiability by replacing the legacy proof
  representation with W3C Data Integrity `eddsa-jcs-2022`, while preserving the
  same Ed25519 key boundary.

## 8. Revocation Status

`GET /api/v1/vc/status/:credential_id`

```json
{
  "credential_id": "urn:uuid:2f4574e6-0ef3-4d87-bc24-5ab5168e6a7a",
  "status": "active",
  "checked_at": "2026-05-04T10:19:00Z",
  "cache_until": "2026-05-04T10:29:00Z"
}
```

Status values:

- `active`
- `revoked`
- `suspended`
- `expired`
- `unknown`

`unknown` cannot upgrade reputation or unlock gated communities.

## 9. Reputation Label Mapping

| Credential state | Labeler tier |
|---|---|
| No VC | `basic` |
| Valid `EmailCredential` | `basic` contactability only |
| Valid `TrisAuraHumanityCredential` | `verified_human` |
| Expired VC | `basic` plus local renewal prompt |
| Revoked/suspended VC | `basic` and security event |
| Unknown status | keep previous tier for display only; block privileged actions |

## 10. Production Constraints

- No mock identity provider in production.
- Issuer signing key cannot live in the mobile app.
- Provider subjects and raw assertions cannot be logged.
- Presentation requires explicit user approval.
- Credential deletion is local unless the user chooses issuer revocation.
- The app must remain usable as a basic forum client without a VC.
