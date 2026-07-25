# Identity Resolution Contract v1

This directory is the single source of truth for the board-reference and public
author behavior verified across the Flutter app, Relay, AppView, and Web.

Runtime code must remain local and offline-capable. No consumer may require a
network call to interpret these rules.

## Rules

- Board references match `id`, then `slug`, then `legacy_ids`.
- Empty references never match.
- Public author labels prefer `handle`, then an abbreviated DID. `display_name`
  remains an optional profile field and is not substituted for identity.
- `anonymous` is returned only when neither a public handle nor an author DID is
  present.

Every consumer verifies this contract during its normal build. Component tests
exercise their existing public API, adapter, renderer, or local model behavior;
the shared verifier checks that the fixtures and declared rules remain valid.

## Constitution Review

This contract preserves local-first operation and identity autonomy. It carries
only public identity presentation fields and does not introduce a service,
network dependency, private identity data, credential claims, or new
distribution path.
