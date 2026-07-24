# P-256 Identity Write Policy

> Status: Accepted for dev rollout
> Date: 2026-07-24
> Scope: First-party App identity, Relay registration, anchors, sync ops, and
> ActivityPub publication intents

## Decision

All new first-party user-identity writes use `p256-sha256` with a
platform-backed, non-exportable key. The Relay rejects new identity
registrations, identity-anchor mutations, sync ops, and ActivityPub
publication intents when the author identity is not P-256.

Ed25519 verification remains available only for reading and independently
verifying historical identity data. This policy does not change
protocol-specific cryptography such as Issuer credential signatures, Relay
snapshots, Nostr events, or third-party federation formats.

The dev rollout uses selective reset:

- preserve posts, boards, content items, Wallet credentials, and subscriptions;
- back up PostgreSQL and device SQLite before mutation;
- remove obsolete dev identity registrations, capabilities, and publication
  queue state;
- remove incompatible local queue/anchor state while retaining source content;
- recreate the device identity in secure hardware and register it again.

## Constitution Review

1. The user-controlled identity is the device-held P-256 identity key.
2. No additional data leaves the device. Existing explicit sync/publication
   choices remain unchanged.
3. Only a public key, signature, DID, and declared custody metadata are needed.
4. No legal identity, provider assertion, private key, biometric data, or raw
   credential claim is introduced.
5. An incompatible legacy identity receives the explicit
   `identity_key_upgrade_required` reason; there is no silent trust downgrade.
6. No personhood commitment or duplicate-prevention key is created or changed.
7. Historical signatures remain verifiable. The dev-only reset is backed up,
   selective, and does not delete user content or Wallet credentials.
8. This policy applies to first-party Relay writes; external protocol
   algorithms remain discoverable through their existing boundaries.

This satisfies identity autonomy by making hardware custody the only
first-party write path and satisfies data autonomy by preserving local content
during the reset.
