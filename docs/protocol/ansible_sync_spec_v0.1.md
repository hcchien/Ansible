# Ansible Sync Spec v0.1

> Status: Draft  
> Owners: core, sync

This document tracks the initial `/inbox` + `/sync/delta` protocol used by `ansible_sync/handlers`.

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

