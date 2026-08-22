# did:elix Method Specification v1

Status: Implemented candidate method specification. This document is the
normative contract for `did:elix` v1; it replaces the legacy
key-and-handle-derived identifier for new identities only. Legacy identifiers
remain valid and use the explicit migration operation below.

This is a project method specification, not a claim that `did:elix` has been
accepted into an external standards registry. The repository, portable
vectors, Universal Resolver-compatible binding, and Relay endpoint
are the interoperability surface for the candidate method.

## Rationale and method choice

The application needs one identifier that remains stable across key recovery,
key rotation, handle changes, and Relay changes while retaining a complete,
independently verifiable update history. The v1 design is intentionally small:
the identifier commits only to public genesis material, while signed anchors
define later state.

Existing method families remain useful for different jobs:

- `did:key` is retained as a wallet/key alias, but a key-derived identifier
  alone does not model this method's recoverable, auditable update chain.
- domain-backed methods are appropriate when a domain operator is meant to be
  the root of resolution; the Elix identity must survive changing Relay or
  domain operators.
- registry or directory-backed methods can provide update logs, but making one
  directory the required authority would violate the project's portability
  constraint.

`did:elix` therefore does not replace those methods universally. It supplies
the application-specific combination of a stable genesis commitment, signed
key transitions, delayed recovery, and Relay-independent verification. The
DID document can still expose chosen `did:key`, `did:plc`, and `at://` aliases.

## Identifier syntax

The method-specific identifier follows this ABNF (RFC 5234):

```abnf
did-elix-v1 = "did:elix:z" 52base32
52base32 = 52(base32-lower)
base32-lower = %x61-7A / %x32-37
```

Only the RFC 4648 lowercase base32 alphabet (`a-z2-7`) is accepted. The `z`
is a version discriminator, not a multibase claim. Percent-encoded and
uppercase forms are not equivalent identifiers.

## Method-specific identifier

`did:elix:z<suffix>` is derived from the SHA-256 digest of the canonical genesis
commitment, encoded as unpadded RFC 4648 base32 with a leading `z`.

The genesis commitment is the ordered JSON object:

```json
{"method":"did:elix","method_version":1,"genesis_key":"<public key>","genesis_nonce":"<32-byte lowercase hex>"}
```

The nonce MUST be generated from a cryptographically secure random source. It
is public, immutable, and prevents handle or later key changes from changing
the DID. The suffix uses the first 32 digest bytes.

The exact algorithm is:

1. UTF-8 encode the canonical commitment shown above;
2. calculate SHA-256 over those bytes;
3. encode all 32 digest bytes as lowercase RFC 4648 base32 without padding;
4. prepend `did:elix:z`.

Unknown commitment properties, uppercase nonce hex, and non-32-byte nonces
MUST be rejected. A genesis key is lowercase hex and is either a 32-byte
Ed25519 public key or a 65-byte uncompressed P-256 public key.

## Registration proof

New accounts sign this fixed-order payload with the genesis identity key:

```json
{"type":"io.trisaura.identity.registration","version":1,"nonce":"<Relay nonce>","did":"<v1 DID>","genesis_commitment":{"method":"did:elix","method_version":1,"genesis_key":"<public key>","genesis_nonce":"<nonce>"}}
```

The Relay validates the commitment and DID before consuming its one-time
nonce. Legacy registration requests without `genesis_commitment` retain their
nonce-only signature contract; a v1-shaped DID without a commitment is never
accepted.

## Anchor chain

Every v1 anchor uses `schema_version: 4` and MUST contain
`genesis_commitment` and an immutable `did`. The initial anchor has no
`prev_anchor_cid`. Each later anchor
MUST reference its immediate predecessor CID. A rotation MUST be authorized by
the previous active identity key and the replacement key; recovery follows the
existing delayed, vetoable recovery policy. A resolver MUST reject missing
links, CIDs that do not match canonical bodies, signature failures, cycles,
and forks without a deterministic, signed successor rule.

`created_at` and device `enrolled_at` use the exact UTC form emitted by the
Dart reference implementation: `YYYY-MM-DDThh:mm:ss.sssZ`, with an additional
three fractional digits only when those microseconds are non-zero. Offsets,
missing milliseconds, and redundant `.000000Z` forms are non-canonical in v4.
Device identifiers are unique within an anchor; device keys are 32-byte
lowercase Ed25519 hex keys; device custody, enrollment time, and identity-key
attestation are all required.

Schema v4 canonical body properties are ordered:

```text
type, schema_version, did, handle, identity_key,
identity_key_algorithm, genesis_commitment, also_known_as, custody_class,
devices, prev_anchor_cid, reason, created_at
```

`sig` is the current anchor identity-key signature over the canonical body.
`device_sig` is the previous identity-key authorization for rotations (or an
allowed active-authority proof for device changes). `recovery_proof` is served
with an activated recovery anchor so independent resolvers can verify that
transition. V1 recovery-code-only transitions are rejected because their
server-side secret check would make the Relay the sole unverifiable authority.
Reason codes are semantic, not decorative: `rotation` and v1 `recovery` change
the active identity key, while `device_change` preserves both the identity key
and its custody class. A mislabeled transition MUST be rejected even when all
supplied signatures are cryptographically valid.

## Resolution

Conforming Relays expose:

- `GET /api/v1/identity/chain/:did` — ordered genesis-to-active anchors;
- `GET /api/v1/identity/did/:did` — a DID Core document plus
  `didResolutionMetadata` containing `methodVersion`, `anchorCid`, and the
  source Relay; and
- `GET /api/v1/identity/migration/:legacyDid` — a signed legacy-to-v1 alias,
  or 404.
- `GET /1.0/identifiers/:did` — a Universal Resolver-compatible DID Resolution
  result envelope.

Clients MUST verify the chain locally. A Relay is an availability source, not
an identity authority. A resolver that has previously observed an active CID
MUST reject any response that does not contain that CID as the same prefix;
clients without a checkpoint SHOULD compare independent Relays and fail closed
on divergent valid successors. Private keys, recovery material, credentials,
legal identity, and biometric material MUST NOT appear in any endpoint.

The DID document projects the active identity key directly from the verified
anchor. Ed25519 keys use the `0xed01` multicodec prefix and base58btc multibase;
P-256 keys use a `JsonWebKey2020` public JWK. The projection does not trust an
alias to supply the verification key. `authentication` and `assertionMethod`
reference that verification method.

## Legacy migration

Existing legacy `did:elix` identifiers remain resolvable. A migration is an
explicit dual-signed object binding the old DID to a separately anchored v1
DID. Its canonical property order is `type`, `version`, `legacy_did`, `v1_did`,
`created_at`; `legacy_sig` and `v1_sig` are signatures by the two active
identity keys over those bytes. Submit it to `POST /api/v1/identity/migration`.
Both DID documents then list the other in `alsoKnownAs`; clients preserve the
old DID as an alias and MUST NOT silently rewrite identity records. Migration
is never created by background sync.

Migration requests reject unknown properties and use the same canonical UTC
timestamp rule. Relay responses preserve the exact signed `created_at` bytes
rather than reconstructing the value from a database timestamp.

## Conformance

Implementations MUST pass the checked-in vectors for genesis derivation,
canonical encoding, rotation, recovery, invalid signature, missing link, fork,
and legacy migration. The portable vectors are in
[`did_elix_v1_conformance_vectors.json`](did_elix_v1_conformance_vectors.json),
with executable Dart and Elixir suites in the app/core and Relay test trees.
New encodings require a new `method_version`.

The JSON file contains deterministic test-only Ed25519 seeds and public keys,
the exact registration signature, complete signed genesis/rotation/recovery
objects, CIDs, a resolvable chain, a signed legacy anchor and migration, plus
concrete malformed objects with expected error codes. Those seeds are fixtures
only and MUST never be used for a real identity.

## DID operations and error behavior

- Create: v1 registration followed by a signed schema-v4 initial anchor.
- Read: resolve and independently verify the complete chain.
- Update: append a dual-authorized rotation, recovery, or device-change anchor.
- Deactivate: account freeze is represented as resolution error `deactivated`;
  destructive key deletion is not inferred from deactivation.

Resolvers fail closed on malformed commitment, unsupported schema, DID/hash
mismatch, bad CID, missing link, fork, signature failure, missing transition
authorization, or frozen state. Relay-specific errors are not silently
converted into a valid DID document.

## Interoperability HTTP binding

An independent implementation can resolve through either binding:

```text
GET /api/v1/identity/chain/{percent-encoded-did}
GET /1.0/identifiers/{percent-encoded-did}
```

The first returns the proof material a client verifies. The second returns the
Universal Resolver-style `didDocument`, `didResolutionMetadata`, and
`didDocumentMetadata` envelope. A 200 response alone is not proof: clients
still verify the full chain and active-key projection against the portable
vectors and rules above.

## Security considerations

- The public genesis nonce prevents deterministic correlation by key alone but
  is not secret and supplies no authorization.
- Collision resistance depends on SHA-256 and the full 32-byte digest encoded
  in the identifier.
- Relay compromise can suppress data or replay a valid historical prefix.
  Cryptography rejects forged bodies, broken links, missing transition proofs,
  and divergent chains presented together, but it cannot prove that one
  availability source disclosed the newest successor. Persisted active-CID
  checkpoints and comparison across independent Relays provide rollback and
  equivocation detection; a first resolution from one Relay has no such
  freshness guarantee.
- Recovery evidence is public authorization metadata only. Recovery codes,
  private keys, biometric results, legal identity, and credentials never enter
  the anchor chain or resolver response.
- Migration is explicit and dual-signed. Resolving an alias does not silently
  rewrite historical identifiers or transfer unrelated credentials.

## Governance and security contact

The repository is the provisional change-control record. Security reports go
to the repository's private security-advisory channel. The Relay publishes a
Universal Resolver-compatible endpoint and portable vectors; submission to a
third-party DID method registry remains a separate governance action after a
public deployment passes an independent resolver run.

## Constitution Review

The method keeps identity independent of any Relay and exposes only chosen
public keys, aliases, endpoints, and signed evidence. It fails closed on chain
integrity errors and does not publish private keys, recovery secrets, legal
identity, credentials, or biometric data. Migration and external publication
remain explicit user-controlled actions.
