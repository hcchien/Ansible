# `did:elix` Method Rationale and Interoperability

> Status: Public architecture note; the method remains project-defined while
> its resolver and operation-log contracts mature.

## Summary

Elix needs one social identity that survives a change of signing key, handle,
home Relay, or hosting operator. No existing DID method used by the project
meets that requirement without either binding the user to an operator or
depending on another network's canonical directory. `did:elix` therefore
names the project's existing self-certifying identity anchor chain; it is not a
new source of trust.

The roles are deliberately separated:

| Identifier | Role | Why |
| --- | --- | --- |
| `did:elix` | Canonical social and federation identity | Stable across key rotation and Relay migration |
| `did:key` / holder-specific DID | Wallet credential holder | Deterministic and independently verifiable |
| `did:web` | Issuer or organization | Connects an accountable operator to its HTTPS domain |
| `did:plc` | Optional AT Protocol bridge | Allows Bluesky interoperability without making `plc.directory` authoritative for every Elix user |

## Why Not Use Only an Existing Method?

### `did:web`

For a person, `did:web` makes the domain operator part of the identity. Moving
from `relay-a.example` to another independent Relay would otherwise change the
DID or require the former operator's cooperation. Elix reserves `did:web` for
issuers and organizations, where domain accountability is useful.

### `did:key`

`did:key` is an excellent holder identifier because a verifier can derive the
DID document without network access. It is not sufficient as the long-lived
social identity: it cannot publish a service endpoint or handle, and replacing
a compromised key produces a different DID. Followers, reputation, and the
account identifier should not be permanently lost merely because a key is
rotated.

### `did:plc`

`did:plc` has the desired portable, operation-log shape, but its canonical
resolution depends on Bluesky's `plc.directory`. Elix is designed for
independently operated Relays and must not make an unrelated operator the sole
authority for every user's identity. Users may opt into a bidirectionally
linked `did:plc` alias when they enable the AT Protocol bridge.

## Identifier and Resolution Model

A `did:elix:<id>` identifier is derived from the signed genesis anchor. Later
anchors form a hash-linked, signed operation chain and can change the current
verification key, handle aliases, and home Relay without changing the DID.

A resolver returns both the projected DID document and the anchor-chain
evidence. A serving Relay is a discovery and availability source, not the
identity authority: clients must verify the chain from genesis. Cross-Relay
resolution and replication must preserve that evidence and must not silently
replace the user's chosen home Relay.

## Keys, Passkeys, and Recovery

These terms are not interchangeable:

- A **Passkey/device-authentication ceremony** confirms a local user action.
- A **device hardware key** is created in Secure Enclave, Android Keystore, or
  an equivalent platform facility. Elix receives its public key and
  signatures, not its private key. It is not included in identity recovery
  backups.
- **Identity recovery material** is the explicit, user-controlled material
  needed by legacy/reduced-trust recovery paths. If exported, it is encrypted
  with the user's passphrase. Recovery creates a new device hardware key.

Platform-synced passkeys may be backup-eligible without exposing raw private
key bytes to Elix. Product copy must therefore describe the particular key and
custody mode instead of claiming that all "passkey private keys" are either
exportable or non-exportable.

## Interoperability and Governance

`did:elix` is currently a project-defined DID method. That creates real costs:
generic DID resolvers will need a method driver, and the operation and
resolution formats require stable versioning. Before claiming broad DID
interoperability, the project must publish:

1. identifier syntax and canonical encoding;
2. genesis and update operation schemas;
3. signature, rotation, recovery, and deactivation rules;
4. DID-document projection and resolution metadata;
5. test vectors and resolver conformance tests;
6. versioning, security-contact, and governance procedures.

Until those artifacts are complete, product and developer documentation must
label the method as project-defined and state which Elix components can resolve
it. Existing standards remain in use at interoperability boundaries rather
than being replaced unnecessarily.

## Constitution Review

- **Identity autonomy:** the DID is independent of a Relay, Issuer, Forum Host,
  AppView, domain, and `plc.directory`; rotation and migration preserve the
  canonical identity.
- **Data autonomy:** resolution publishes only user-chosen public identity
  metadata and signed anchor evidence. Private keys, recovery secrets,
  credentials, and biometric data are excluded.
- **Minimal disclosure:** a `did:elix` identifier and document do not imply a
  verified-human tier or disclose legal identity.
- **Exit and recovery:** users can rotate keys and move between compatible
  Relays. Reduced-trust/exportable recovery paths must remain explicit until
  the hardware-custody compliance gap is closed.
- **Known compliance gap:** the repository compliance review still identifies
  legacy exportable key paths and incomplete external-host policy use. This
  note does not claim that those gaps are resolved.

## Related Documents

- [Layered identity and method implementation plan](../superpowers/plans/2026-06-16-layered-identity-did-method-plan.md)
- [Engineering constitution](../superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md)
- [Current constitution compliance review](../superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md)
