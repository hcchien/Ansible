# Ansible Sync Spec v0.1

> Status: Draft
> Owners: core, sync

This document tracks the initial `/inbox` + `/sync/delta` protocol used by `ansible_sync/handlers`.

Identity proofing is intentionally out of scope for this sync envelope. The
planned production direction is documented separately:

- [`tris_aura_vc_wallet_spec_v0.1.md`](./tris_aura_vc_wallet_spec_v0.1.md)
- [`../architecture/tw_digital_identity_vc_wallet.md`](../architecture/tw_digital_identity_vc_wallet.md)

Forum sync records should carry DIDs, signatures, and content operations. They
must not carry raw Taiwan digital identity assertions, national identifiers, or
Wallet credential payloads.

Follow users / follow boards is also modeled as a separate social subscription
layer. Its design is documented in
[`../superpowers/specs/2026-05-04-follow-users-boards-design.md`](../superpowers/specs/2026-05-04-follow-users-boards-design.md).
Content sync may transport ActivityPub-compatible follow activities through
`/inbox`, but normal post/thread delta records should remain content-focused.

## Resources

- `/inbox` – accepts ActivityPub-compatible envelopes that eventually hydrate `ansible_core/store`.
- `/sync/delta` – stateless pull endpoint returning Drift-compatible mutations for nodes.

## Envelope

```json
{
  "id": "uuid",
  "actor": "did:key:alice",
  "type": "Create",
  "object": {},
  "signature": "..."
}
```

## TODO

- Define merkle root calculation for delta stream.
- Enumerate replay protection rules.
- Describe pagination contract.
- Define how verified-human reputation labels are referenced without embedding
  VC payloads into sync envelopes.
