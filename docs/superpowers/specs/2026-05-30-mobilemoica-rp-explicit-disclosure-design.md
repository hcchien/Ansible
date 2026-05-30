# MobileMoica RP Explicit Disclosure Design

> Status: Draft, not approved for implementation
> Date: 2026-05-30

## Goal

Define a separate MobileMoica / TW FidO relying-party path for issuing a
`TrisAuraHumanityCredential` after explicit user disclosure. This path is not
zkID. It does not provide zero-knowledge proof generation, and it must not be
presented as a zkID or proof-only credential flow.

The goal of this document is to make the data boundary and approval gates clear
before any implementation code is written.

## Scope

This design covers:

- Elix opening the TW FidO app through the MobileMoica APP2APP deep link.
- A first-party server-side MobileMoica RP Broker holding service credentials
  and requesting short-lived MobileMoica tickets.
- User-entered national ID being used only for the ticket request after an
  explicit disclosure screen.
- Issuer verification of the returned PKCS#7 signed response and certificate
  chain.
- Issuer-side duplicate prevention through a keyed, domain-separated
  commitment.
- Issuance of a normal `TrisAuraHumanityCredential` that contains no raw legal
  identity.

This design excludes:

- zkID / OpenAC proof generation.
- Shipping MobileMoica service credentials in Elix.
- Forum Host, Relay, AppView, VC, log, analytics, crash-report, or federation
  exposure of raw identity data.
- Treating this path as the default account creation or default forum
  participation path.
- Enabling production issuance before legal, privacy, security, and
  constitution approval gates are complete.

## Constitution Review

This design touches identity, credentials, Wallet, Issuer, verification, and
forum trust behavior. The constitution applies.

The constitution allows explicit user disclosure as a prerequisite for access
to raw legal identity, but it also says system integrity must not justify
collecting raw legal identity. Because this flow requires the service provider
to process a raw national ID to obtain a MobileMoica ticket, it is not
constitution-compliant by default for ordinary forum anti-abuse.

Implementation is blocked until one of these decisions is recorded:

1. Product, legal, privacy, and security reviewers decide that this optional
   explicit-disclosure RP flow is constitution-compliant for the selected
   product surface because the user affirmatively chooses disclosure for a
   specific credential issuance purpose.
2. The constitution is amended to allow this narrow MobileMoica RP issuance
   path with explicit user disclosure, retention limits, and audit controls.
3. The feature remains disabled and unavailable in production.

Any implementation must still preserve these hard boundaries:

- Raw national ID, legal name, certificate subject, certificate serial,
  provider assertion, and raw PKCS#7 response must not appear in public
  credentials, Relay payloads, Forum Host payloads, AppView payloads, logs,
  analytics, crash reports, or federation payloads.
- Raw provider identifiers must not be used directly as duplicate keys.
- Opaque duplicate-prevention commitments must be keyed, domain-separated,
  non-reversible, and stored only by the Issuer for enforcement.
- Low-assurance account and forum use must remain available without legal ID.
- The UI must clearly say this is an explicit legal-identity disclosure flow and
  not a zero-knowledge flow.

Existing known gaps still apply: hardware-backed key storage and external host
constitution compliance levels are not solved by this design.

## Legal And Privacy Review Gate

This design is a technical proposal, not legal advice. Production work must not
start until counsel and privacy reviewers approve:

- Whether Tris-Aura may act as a MobileMoica relying party for the planned
  credential issuance purpose.
- The relying-party terms, service application obligations, and permitted use of
  MobileMoica results.
- User notice and consent copy, including what raw data is sent to Tris-Aura,
  what is sent to the MobileMoica platform, what is retained, and for how long.
- Retention and deletion rules for transient offers, replay records, consent
  receipts, duplicate-prevention commitments, issued VC metadata, and audit
  events.
- Data subject request handling for access, deletion, correction, and support.
- Incident response obligations for national ID, service credential, ticket, or
  signed-response exposure.
- Whether a separate data protection assessment, vendor filing, or relying-party
  registration artifact is required.

The implementation must fail closed unless the deployed environment references
approved review artifact IDs for legal, privacy, security, and constitution
approval.

## Architecture

Add a server-side `MobileMoicaRPBroker` under the Issuer boundary. The Broker is
the only component that holds MobileMoica service credentials and calls
MobileMoica APIs. Elix never receives service credentials or computes provider
checksums.

The Issuer remains responsible for:

- creating offer IDs and holder-binding challenges,
- verifying Wallet holder control before issuing,
- verifying the Broker result,
- deriving and storing the duplicate-prevention commitment, and
- issuing the VC.

The Broker is responsible for:

- requesting a short-lived MobileMoica ticket after explicit disclosure,
- binding the ticket to a Tris-Aura offer, holder DID, nonce, purpose, consent
  version, and expiry,
- returning a MobileMoica APP2APP deep link to Elix,
- polling MobileMoica for the signing result,
- validating the PKCS#7 signature, signed content, certificate chain, expiry,
  and revocation status, and
- returning only normalized verification facts to the Issuer.

Relay, Forum Host, and AppView consume only the resulting VC or derived trust
tier after issuance. They never receive MobileMoica artifacts.

## User Flow

1. User opens Wallet and chooses `MobileMoica Verified Human`.
2. Elix shows an explicit disclosure screen before collecting national ID.
3. User enters national ID and confirms disclosure for the credential issuance
   purpose.
4. Elix sends holder DID, holder proof, national ID, consent version, and locale
   to the Issuer start endpoint over TLS.
5. Issuer creates an offer and asks the Broker to request a MobileMoica ticket.
6. Broker creates signed content that binds offer ID, holder DID, issuer origin,
   purpose, consent version, nonce, and expiry.
7. Broker requests a short-lived MobileMoica ticket.
8. Issuer returns offer ID, expiry, and APP2APP deep link to Elix.
9. Elix opens the TW FidO app through the `mobilemoica` scheme.
10. User authorizes signing inside TW FidO.
11. TW FidO returns control to Elix through the configured return URL.
12. Elix polls Issuer status for the offer. The production polling cadence
    should follow the MobileMoica SP-API-ATH-02 recommendation of at least four
    seconds between result queries.
13. Broker fetches the signing result, verifies it, derives normalized facts,
    and discards raw MobileMoica artifacts.
14. Issuer stores only the issuer-keyed TW national-ID commitment created from
    the explicit disclosure and marks the offer verified.
15. Elix asks Issuer to issue the VC with a fresh holder proof.
16. Issuer issues and returns a `TrisAuraHumanityCredential`.
17. Wallet stores the VC and shows the credential as explicit-disclosure
    MobileMoica verified human.

## Explicit Disclosure UI Requirements

The pre-disclosure screen must be a blocking step before national ID entry. It
must state:

- This is MobileMoica / TW FidO relying-party verification.
- This is not zkID and not a zero-knowledge proof.
- Tris-Aura Issuer will receive the entered national ID for the limited purpose
  of requesting a one-time MobileMoica ticket.
- The MobileMoica platform will receive the ticket request and signing request.
- The Issuer may transiently process the returned signed response and
  certificate data to verify the result.
- The issued VC will not contain national ID, legal name, certificate subject,
  certificate serial, provider assertion, signed response, or duplicate
  commitment.
- Refusing this flow does not block low-assurance use.

The confirm action must create a consent receipt with:

- consent version,
- product surface,
- purpose,
- holder DID,
- offer ID,
- timestamp,
- locale, and
- hash of the exact disclosure copy.

The receipt must not include national ID, legal name, signed response, or
certificate subject fields.

## API Shape

### Start MobileMoica Offer

`POST /api/v1/vc/mobilemoica/start`

Request:

```json
{
  "holder_did": "did:key:holder",
  "holder_proof": "base64url-signature",
  "consent_version": "mobilemoica-rp-v1",
  "consent_copy_hash": "sha256:copy-hash",
  "national_id": "user-entered-id",
  "locale": "zh-Hant-TW"
}
```

Response:

```json
{
  "offer_id": "mobilemoica-offer-id",
  "expires_at": "2026-05-30T12:05:00Z",
  "deep_link_url": "mobilemoica://..."
}
```

The request body is sensitive. Handlers must use redacted request logging. The
`national_id` field must be consumed in memory for ticket creation and then
discarded.

### Check MobileMoica Offer Status

`GET /api/v1/vc/mobilemoica/status/{offer_id}`

Response while pending:

```json
{
  "status": "pending",
  "expires_at": "2026-05-30T12:05:00Z"
}
```

Response after verification:

```json
{
  "status": "verified",
  "assurance_method": "mobilemoica_rp_explicit_disclosure",
  "jurisdiction": "TW"
}
```

Error states must use stable codes such as `expired`, `cancelled`,
`invalid_signature`, `revoked_certificate`, `state_mismatch`, and `replay`.
Responses must not echo national ID, signed response, certificate fields, or
provider subject values.

### Issue MobileMoica Credential

`POST /api/v1/vc/mobilemoica/issue`

Request:

```json
{
  "offer_id": "mobilemoica-offer-id",
  "holder_did": "did:key:holder",
  "holder_proof": "base64url-signature"
}
```

Response:

```json
{
  "vc": {
    "type": ["VerifiableCredential", "TrisAuraHumanityCredential"],
    "credentialSubject": {
      "id": "did:key:holder",
      "humanVerified": true,
      "assuranceLevel": "high",
      "assuranceMethod": "mobilemoica_rp_explicit_disclosure",
      "jurisdiction": "TW",
      "disclosureModel": "explicit_rp"
    }
  }
}
```

The real VC response includes issuer, issuance, expiry, status, proof, and
context fields following the existing Issuer VC format. It must not include
MobileMoica raw identity data, provider artifacts, or duplicate-prevention
commitments.

## Signed Content Binding

The content signed through MobileMoica must be deterministic UTF-8 JSON with
canonical field ordering. It must include:

- `schema`: `trisaura.mobilemoica_rp.v1`
- `issuer_origin`
- `offer_id`
- `holder_did`
- `purpose`: `issue_trisaura_humanity_credential`
- `consent_version`
- `consent_copy_hash`
- `nonce`
- `issued_at`
- `expires_at`

The Broker must verify that the returned PKCS#7 signed content exactly matches
the stored offer content before marking an offer verified.

For the production MobileMoica ticket request, the Broker must use APP2APP
signing mode: `op_code=SIGN`, `op_mode=APP2APP`, `sign_type=PKCS#7`,
`tbs_encoding=base64`, and `hash_algorithm=SHA256`. The deterministic signed
content must fit within the MobileMoica `sign_data` limit; if it does not, the
Broker must fail closed before requesting a ticket.

The APP2APP deep link must use
`mobilemoica://moica.moi.gov.tw/a2a/verifySign` with `sp_ticket`, `rtn_url`,
and `rtn_val`. `rtn_url` and `rtn_val` must be Base64URL encoded and must not
carry raw identity data.

The Elix app link handler must accept `trisaura://mobilemoica/callback` as a
normal return-to-app signal and must not route it through unrelated web-session
approval parsing.

## Data Handling

| Data | Allowed Location | Retention | Rule |
| --- | --- | --- | --- |
| MobileMoica service credentials | Server KMS or secret manager only | Until rotated | Never commit, log, expose to app, or include in diagnostics |
| National ID | Elix memory, Issuer handler memory, Broker request memory | Request lifetime only | Never persist; redact request logs before parsing failures |
| MobileMoica ticket | Broker encrypted offer state, Elix memory for deep link | Until offer expiry | Treat as bearer material; never log |
| Return URL parameters | Elix memory, Issuer status state | Until offer expiry | Must not carry raw identity data |
| Signed response / PKCS#7 | Broker memory | Verification lifetime only | Never store by default; legal retention requires separate approval |
| Certificate subject fields | Broker memory | Verification lifetime only | Extract only for verification; never persist or issue |
| Provider hashed subject | Broker memory | Verification lifetime only | Use only to verify MobileMoica result integrity; do not use as the cross-method duplicate key |
| TW national-ID commitment | Issuer duplicate-prevention store | Active credential lifetime plus approved replay window | Keyed, domain-separated, non-reversible; shared with Passport NFC `national_id_hash` namespace |
| Consent receipt | Issuer audit store | Approved legal retention period | No national ID, legal name, signed response, or certificate subject |
| Issued VC | Wallet and Issuer metadata stores | Existing VC retention rules | No raw identity, provider artifacts, or commitments |

## Duplicate Prevention

The Issuer derives the MobileMoica duplicate-prevention key from the normalized
national ID explicitly entered for this RP flow:

```text
tw_national_id_commitment = HMAC-SHA256(
  SUBJECT_COMMITMENT_PEPPER,
  "tw_national_id_v1:" ||
  normalized_national_id
)
```

This intentionally uses the same issuer-only namespace as Passport NFC
`national_id_hash` for TW national-ID backed personhood, so the same person
cannot obtain two active high-assurance credentials through MobileMoica and
Passport NFC at the same time. The raw national ID must be discarded after
commitment derivation.

Provider returned subjects, certificate subjects, certificate serials, and
signed responses are verification inputs only. They must not become the
cross-method duplicate key and must not be persisted by default.

If an active credential already uses the same commitment, Issuer rejects new
issuance with a generic duplicate error (`duplicate_active_credential` for
MobileMoica issue or `personhood_already_bound` for Passport issue). The VC
response must not reveal which prior account or credential owns the binding.

## Constitution Review

- Identity and credential: the holder Wallet DID receives a
  `TrisAuraHumanityCredential`; MobileMoica/TW FidO is only an optional
  high-assurance path.
- Data leaving device: national ID leaves Elix only after explicit disclosure
  and only to request/verify the one-time MobileMoica ticket.
- Minimum claim: the VC contains verified-human, TW jurisdiction, assurance
  method, and disclosure model only.
- Exclusions: raw national ID, legal name, certificate serial, certificate
  subject, signed response, provider assertion, and duplicate commitment remain
  out of VC subjects, Relay payloads, forum posts, federation payloads, and
  normal logs.
- Duplicate prevention: Issuer stores a keyed, domain-separated,
  non-reversible TW national-ID commitment only where needed to enforce one
  active high-assurance binding.
- Exit/lower trust: users may refuse this flow and continue using lower
  assurance paths.

## Verification Requirements

The Broker must verify:

- MobileMoica result checksum or equivalent provider authenticity mechanism.
- PKCS#7 signature over the exact stored signed content.
- Certificate chain to approved trust anchors.
- Certificate validity time.
- Certificate revocation through the approved CRL or OCSP path.
- Offer ID, holder DID, nonce, consent version, purpose, and expiry binding.
- Single-use offer and replay ID.

If revocation checking is unavailable, production issuance must fail closed.

### MobileMoica Checksum Handling

The Issuer provider implements the MobileMoica v2.9 checksum construction
server-side only:

- concatenate request fields in the documented order for ticket and result
  payloads;
- compute SHA-256 over the UTF-8 payload and encode it as lowercase hex;
- AES-GCM encrypt the digest hex string with the MobileMoica API AES key;
- encode `IV || ciphertext || tag` as lowercase hex, using a fresh IV for
  generated `sp_checksum` values and fixed-IV vectors only for interoperability
  tests;
- parse the IV from provider-returned checksums before verification.

Elix never receives the MobileMoica AES key and never computes `sp_checksum` or
`idp_checksum`.

The Issuer provider also parses the MobileMoica `sp_ticket` envelope by
verifying `BASE64URL(SHA256(BASE64URL(payload)))` before using
`transaction_id` or `sp_ticket_id` for result polling.

## Logging And Observability

Allowed counters:

- `mobilemoica_offer_started`
- `mobilemoica_deeplink_opened`
- `mobilemoica_result_verified`
- `mobilemoica_result_replay`
- `mobilemoica_invalid_signature`
- `mobilemoica_revoked_certificate`
- `mobilemoica_offer_expired`
- `mobilemoica_issue_duplicate`
- `mobilemoica_issue_success`

Logs and counters must not include national ID, legal name, certificate subject,
certificate serial, signed response, provider hashed subject, ticket,
MobileMoica service credentials, request body, or return URL query values.

## Failure Behavior

The flow must fail closed when:

- legal, privacy, security, or constitution approval artifact IDs are absent;
- MobileMoica service credentials are missing or fail validation;
- `MOBILEMOICA_RP_ENABLED` is not explicitly true;
- holder proof is invalid;
- consent version is unsupported;
- ticket request fails;
- the TW FidO app cannot be opened;
- the user cancels authorization;
- the offer expires;
- signed content does not match the stored offer;
- certificate chain or revocation verification fails;
- replay is detected; or
- duplicate active personhood commitment exists.

User-facing errors must be concise and must not echo provider artifacts.

## Rollout Gates

Production enablement requires all of these gates:

1. Legal approval artifact ID recorded in deployment config.
2. Privacy approval artifact ID recorded in deployment config.
3. Security approval artifact ID recorded in deployment config.
4. Constitution approval or amendment artifact ID recorded in deployment config.
5. MobileMoica relying-party credentials provisioned through server-side secret
   management.
6. Certificate trust anchors and revocation configuration validated at startup.
7. Redaction tests proving sensitive request and response fields are not logged.
8. True-device test proving Elix opens TW FidO, returns to Elix, verifies the
   result, and issues a VC with no raw identity in the VC.
9. Relay and Forum Host tests proving only the VC trust tier is consumed.
10. Support runbook for deletion, duplicate-binding disputes, credential
    revocation, and service credential rotation.

## Implementation Phases

### Phase 0: Approval And Fail-Closed Config

Add config fields and startup checks that keep the feature unavailable until all
approval artifact IDs and MobileMoica server credentials are present.

### Phase 1: Broker Boundary

Implement `MobileMoicaRPBroker` with a fake verifier for tests and a production
adapter that fails closed until MobileMoica HTTP calls, credentials, trust
anchors, PKCS#7 validation, and revocation checking are configured.

### Phase 2: Issuer API And Data Store

Add start, status, and issue endpoints with holder proof checks, consent
receipt persistence, offer state, replay tracking, commitment derivation, and
VC issuance.

### Phase 3: Elix Explicit-Disclosure UX

Add a new Wallet credential screen that explains the disclosure model, collects
national ID only after confirmation, opens the MobileMoica deep link, polls
status, and stores the issued VC.

### Phase 4: Production Verification

Implement MobileMoica APP2APP PKCS#7 ticket creation, result polling using the
provider checksum and `sp_ticket` helpers, PKCS#7 validation, chain validation,
and revocation checking.

### Phase 5: Limited Pilot

Run a limited true-device pilot with production logging disabled for sensitive
payloads, audit-safe counters enabled, and support procedures ready.

## Acceptance Criteria

- The feature is disabled by default and unavailable without legal, privacy,
  security, and constitution approval artifact IDs.
- Elix never contains MobileMoica service credentials.
- A true device can open TW FidO through MobileMoica APP2APP and return to
  Elix.
- Issuer verifies the MobileMoica result and issues a
  `TrisAuraHumanityCredential` only after explicit user disclosure.
- The issued VC contains only holder DID, human verification status, assurance
  metadata, jurisdiction, disclosure model, status, expiry, issuer, and proof.
- No national ID, legal name, certificate subject, certificate serial, provider
  assertion, signed response, ticket, service credential, provider hashed
  subject, or duplicate-prevention commitment appears in VC payloads, logs,
  Relay payloads, Forum Host payloads, AppView payloads, analytics, crash
  reports, or federation payloads.
- Duplicate active personhood binding is rejected through a keyed commitment.
- Low-assurance use remains available without MobileMoica verification.
