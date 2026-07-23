# Taiwan Cross-Method Person Binding Design

> Status: Approved direction; cryptographic implementation required before
> production enforcement
>
> Date: 2026-07-23

## Goal

Prevent one Taiwan citizen from obtaining multiple simultaneously active
high-assurance credentials by switching between Passport NFC and MobileMoica,
including when the credentials are requested for different holder DIDs.

The duplicate key is the Taiwan national identifier carried in the passport
personal-number field and verified by MobileMoica. Holder DID remains the
credential subject and is not the person-level duplicate key.

## Current Gap

The current ZKPassport verifier derives both `national_id_hash` and
`passport_number_hash` from ZKPassport's passport-level
`uniqueIdentifier`. That value does not prove or represent the Taiwan national
identifier. MobileMoica derives its commitment from the verified national
identifier, so the two production paths do not currently share a namespace
even though tests can inject matching strings.

The existing ZKPassport-derived `national_id_hash` MUST NOT be treated as a
cross-method Taiwan person binding.

## Canonical Input

Both verification methods normalize the Taiwan national identifier as:

1. trim surrounding whitespace;
2. convert ASCII letters to uppercase;
3. reject filler characters and any value that does not pass the Taiwan
   national-ID syntax and checksum;
4. encode the accepted value as ASCII.

Passport obtains this value from the authenticated DG1/MRZ personal-number
field. MobileMoica obtains it from the value covered by the verified broker
ceremony. A value typed by the user is never sufficient evidence on its own.

## Commitment Protocol

The durable duplicate key is:

```text
verified_input = first_31_bytes(
  SHA-256("tris-aura:person-binding:tw:v1" || normalized_national_id)
)
tw_person_binding_v1 = HMAC-SHA-256(
  issuer_person_binding_pepper,
  "tw_national_id_v1" || 0x00 || canonical_field(verified_input)
)
```

`verified_input` exists only inside the private Verifier-to-Issuer request and
MUST NOT be logged, stored, returned to Wallet, included in a VC, or sent to
Relay/AppView. The private, rotating Issuer pepper prevents offline
enumeration of the low-entropy national-ID space. Persisting plain SHA-256, a
public salt, or an app-embedded HMAC key is prohibited. A future VOPRF may
further reduce trust in the private verification boundary without changing
the durable duplicate index.

### MobileMoica

The broker verifies the MobileMoica result and establishes that the normalized
identifier was covered by the ceremony. Inside the Issuer trust boundary it
computes `verified_input`, immediately wraps it with the Issuer pepper,
persists only `tw_person_binding_v1`, and discards the raw identifier and
provider artifacts according to the approved retention policy.

### Passport NFC

The Wallet authenticates DG1 through SOD/passive authentication and proves all
of the following:

- the personal-number input came from the authenticated passport DG1;
- the identifier passes the Taiwan normalization and checksum rules;
- `verified_input` was formed from that same normalized identifier;
- nationality is `TWN`;
- the proof is bound to the Issuer challenge, holder DID, scope, and expiry.

The verifier confirms the custom proof is chained to the same authenticated
DG1 commitment and challenge-bound disclosure proof, then sends
`verified_input` only over its private authenticated channel to the Issuer.
Neither the verifier API nor ordinary Issuer request logs receive the raw
personal number.

This requires a dedicated circuit/extension. ZKPassport's current
passport-level `uniqueIdentifier` is not a substitute.

## Issuance Semantics

The Issuer atomically enforces one active record per
`tw_person_binding_v1`.

- same binding and same holder DID: return an idempotent existing-credential
  result; do not mint another credential;
- same binding and a different holder DID: return a generic
  `personhood_already_bound` response and require credential recovery or
  replacement;
- new binding: issue the eligible credentials;
- replacement: prove control through the recovery ceremony, revoke the old
  credential, and atomically bind the replacement credential;
- revocation without approved replacement follows the existing re-enrolment
  policy and audit requirements.

The response MUST NOT reveal which DID, credential, or verification method
already owns a colliding binding.

## Credential Claims

Successful Taiwan verification issues a separate
`TaiwanCitizenshipCredential`. If the verification proof also establishes
`age >= 18`, it may issue a separate `AgeOver18Credential`.

The credentials contain neither the national identifier nor
`tw_person_binding_v1`. Date of birth is reduced to the boolean age predicate
before issuance and is not retained.

## Migration

Existing `zkp-national-v1_*` values are passport-level identifiers, not Taiwan
national-ID commitments. They cannot be silently relabelled or migrated.

After the new flow is deployed:

1. new Passport and MobileMoica issuance uses only
   `tw_person_binding_v1`;
2. an existing holder upgrades by completing either verification flow;
3. the Issuer links the new binding to the existing active credential only
   after holder authorization;
4. legacy bindings remain valid for status/revocation but do not claim
   cross-method deduplication.

## Constitution Review

- **Identity involved:** a self-custody holder DID and optional Taiwan
  citizenship/age credentials.
- **Data leaving the device:** Passport sends a challenge-bound proof that
  reveals only the request-scoped `verified_input`, not the raw national
  identifier. MobileMoica sends
  identity material only through the explicitly approved broker ceremony.
- **Minimum claims:** citizenship and the boolean `age >= 18` predicate are
  separate credentials so a holder can present only the required claim.
- **Raw identity exclusions:** national ID, passport number, legal name,
  birth date, raw MRZ/DG1, provider assertions, and certificate subjects do not
  enter VCs, Relay/AppView payloads, ordinary logs, or federation.
- **Duplicate prevention:** the stored binding is issuer-keyed,
  domain-separated, non-reversible, hidden from ordinary verifiers, and
  enforced atomically.
- **Recovery:** a collision on another DID does not reveal the prior identity;
  it routes to the user-controlled recovery/replacement ceremony.
- **Low-assurance access:** ordinary local use remains available without legal
  identity verification.
