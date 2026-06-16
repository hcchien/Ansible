# Tris-Aura Federation Strategy v0.1

> Status: Draft  
> Date: 2026-05-09  
> Owners: core, identity, sync, relay

## Purpose

Tris-Aura is a local-first authoring and reflection system. Federation is an
output path, not the canonical data model. The app should keep its own local
domain model and project public content into external protocols only when the
user chooses to distribute it.

This strategy supersedes the assumption that the public path must be only
AT Protocol / `did:plc`. The current AT Protocol-shaped implementation remains
valid as an implementation context, but future federation work should treat
Nostr and ActivityPub as first-class distribution adapters.

## Canonical Model

The canonical model remains Ansible-native and protocol-neutral:

- `ContentItem` stores local content across `murmur`, `note`, `post`, and
  `discussion` modes.
- `FollowEdge` stores social subscription state.
- Visibility is an Ansible domain decision, not a protocol field.
- Drift SQLite remains the local source of truth for private drafts, local
  content, and publication state.
- Forum Hosts own discussion boards. Local `Board` rows are projections used for
  routing, display, cache, and offline reads while the host-owned board identity
  remains `(forumHostId, hostedBoardId)`.
- `murmur` and `note` remain local canonical content. They may be projected to
  Forum Hosts, Nostr relays, or ActivityPub via relay adapters without changing
  local ownership.
- Local-only personal grouping belongs to `LocalCollection`, not to discussion
  boards.

Nostr events and ActivityPub activities are projections. They must not become
the only persisted representation of user content.

## Identity Model

A single local account runs **one root Ed25519 key with role-specific DID
representations**, with exactly **one canonical** identity. The full design,
the `did:elix` method sketch, the cross-relay resolution protocol, and the
issuer trust model live in the
[layered identity & `did:elix` method plan](../superpowers/plans/2026-06-16-layered-identity-did-method-plan.md).
Summary:

| Identifier | Role | Canonical? |
|---|---|---|
| `did:elix:<id>` | Social / federation identity (the identity itself); domain-independent, portable across relays, resolved via the cross-relay resolution protocol over the self-certifying anchor chain | **Yes — the only canonical** |
| `did:key:<mb>` | Wallet / VC holder (same root key, encoded); universal verifier interop | No — role alias |
| `did:plc:<hash>` | atproto / Bluesky face, **minted only on opt-in bridge**, published to `plc.directory`, bound by `alsoKnownAs` + shared key | No — opt-in alias |
| `did:web:issuer.<domain>` | **Issuer / org** identity (a different actor, not a user) | n/a |
| `did:nostr:<pubkey>` / `npub` | Public Nostr author identity and event signing key | Nostr-facing alias |
| NIP-05, e.g. `alice@elix.cool` | Human-readable display/search identifier | — |

Rules:

- The user's identity *is* `did:elix`. `did:web` is **never** used for user
  identity (it would bind users to one operator's domain and break portability
  across relays — Base Rule 1); it is reserved for issuer/org identity.
- `did:key` is the wallet/VC holder role of the **same** root key; verifiers
  resolve it with zero infrastructure.
- `did:plc` is an **opt-in** atproto alias, not the canonical identity and not
  required for the network to operate; it is bound to `did:elix` via
  bidirectional `alsoKnownAs` + shared/cross-signed key (one-directional
  claims are never trusted).
- Nostr clients follow public keys, not NIP-05 names or AT Protocol handles.
- ActivityPub actors are canonicalized by the relay domain, e.g.
  `@alice@relay.elix.cool`.
- `did:nostr` is the public DID method for Nostr-facing identity.

## Distribution Topology

The app and relay have different responsibilities:

```text
Private/local:
  App only

Nostr:
  App -> user-selected Nostr relays
  App -> optional Ansible relay mirror

ActivityPub:
  App -> signed publication intent -> Ansible relay
  Ansible relay -> ActivityPub inbox/outbox federation
```

The app may publish directly to Nostr relays because Nostr is client-to-relay by
design. The app must not implement ActivityPub federation endpoints. ActivityPub
requires stable HTTPS Actor URLs, inbox/outbox endpoints, WebFinger, delivery
retry, and server-to-server policy handling; those belong in the relay layer.

Principle:

> App signs intent. Relay distributes protocol-specific activities.

## Publication Signing Policy

Local-first storage and federation signing are separate concerns:

- `private` content may remain unsigned local state because it never leaves the
  local database.
- `unlisted` and `public` content must not be distributed until the app has
  created a signed publication intent or signed Nostr event with a real user
  private key.
- Development signatures and stub signatures must never be silently accepted on
  public distribution paths. If production signing is unavailable, the app must
  leave the target pending or failed with an explicit error.
- The app may save content locally before signing succeeds, but external
  adapters must fail closed: no signature, no federation.
- Signing policy must be enforced at adapter boundaries as well as UI flows, so
  alternate entry points cannot bypass it.

## Visibility Semantics

| Ansible visibility | Federation behavior |
|---|---|
| `private` | Local only. No Nostr event, no ActivityPub activity, no relay publication intent. |
| `unlisted` | Distribution is allowed, but relay/app should avoid prominent profile or index placement. This is not a privacy boundary. |
| `public` | Distribution is allowed to Nostr relays and/or ActivityPub actor outbox, depending on user settings. |

Federation visibility must never be treated as encryption. If private or
restricted sharing is needed later, use explicit encryption and state that the
payload is still distributed.

## Nostr Protocol Baseline

The Nostr adapter should use existing NIPs rather than inventing equivalent
protocol shapes:

| NIP | Use in Tris-Aura |
|---|---|
| [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) | Event envelope, event id, secp256k1 Schnorr signatures, WebSocket relay flow. |
| [NIP-02](https://github.com/nostr-protocol/nips/blob/master/02.md) | Follow/contact list projection. |
| [NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) | DNS-based identifier such as `alice@elix.cool`; store and follow pubkeys, not handles. |
| [NIP-09](https://github.com/nostr-protocol/nips/blob/master/09.md) | Deletion request events for public Nostr content. |
| [NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) | User-facing identifiers such as `npub`, `note`, `nevent`, and `naddr`. |
| [NIP-23](https://github.com/nostr-protocol/nips/blob/master/23.md) | Long-form note/article projection using `kind:30023`; drafts may use `kind:30024` only if explicitly distributed. |
| [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) | Future encrypted payloads. Not an MVP privacy boundary and not a substitute for local-only private content. |
| [NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md) | Encrypted private key backup/export/import. Default app storage remains Keychain/Secure Enclave where available. |
| [NIP-65](https://github.com/nostr-protocol/nips/blob/master/65.md) | Relay list metadata (`kind:10002`) for read/write relay preferences. |

MVP mapping:

- Public `murmur` -> `kind:1`.
- Public `note` -> `kind:30023`.
- Delete -> `kind:5`.
- Follow graph -> `kind:3` contact list.
- Relay preferences -> `kind:10002`.

## ActivityPub Relay Responsibilities

The relay/distribution server owns ActivityPub interoperability:

- WebFinger discovery for `@user@relay-domain`.
- Actor JSON under the relay domain.
- Inbox and outbox endpoints.
- `Create`, `Update`, `Delete`, `Follow`, `Accept`, `Reject`, and `Undo`
  activity handling where supported by the current product surface.
- Delivery retries and remote instance error tracking.
- Mapping remote replies, mentions, and follows back into Ansible domain events.

The app sends signed publication intents to the relay. The relay validates the
intent, projects it to ActivityPub, and records delivery status.

## Forum Host Board Ownership

Discussion boards are not local-canonical objects. A Forum Host owns hosted
boards, threads, posts, permissions, moderation state, and distribution FE
state. The app stores:

- `ForumHost` records for configured distribution hosts.
- `HostedBoardProjection` records for local board cache/routing.
- `BoardSubscription` records for read/write opt-in and per-board cursors.
- `BoardPublicationTarget` records for thread drafts, cross-posts, and
  note/murmur projections.

During migration, existing local `Board` rows remain valid as projections. New
discussion board creation should select a Forum Host and create a hosted board
there first. Multi-host distribution uses one primary hosted board plus
cross-post targets; it must not invent a shared multi-primary board identity.

## Failure Behavior

- Nostr publish can partially succeed. Store per-relay publish status.
- ActivityPub delivery can partially succeed. Store per-target delivery status
  and retry in the relay.
- Deletion is best-effort in both ecosystems. Internally, Ansible tombstones are
  authoritative for local state.
- Private content must fail closed: no adapter may publish it.

## Explicit Non-MVP

- NIP-26 delegation is not used in v1.
- The app does not implement ActivityPub server endpoints.
- Private content is not federated.
- ActivityPub followers-only delivery is not treated as private encryption.
- AT Protocol / `did:plc` is not the required public federation identity.

## Implementation Gates

1. Define protocol-neutral publication intent and outbox state.
2. Add Nostr identity, event serialization, signing, and projection.
3. Add app-side Nostr relay publish/read.
4. Add relay-side ActivityPub Actor, WebFinger, inbox/outbox, and delivery.
5. Add UI distribution settings tied to visibility.
6. Clean up docs/tests that assume `did:plc` is the only public identity path.
