# Federation Strategy Design Spec

> Status: Draft for implementation planning  
> Date: 2026-05-09  
> Scope: Tris-Aura App, `ansible_core/store`, `ansible_core/domain`,
> `ansible_core/ap`, future `ansible_core/nostr`, and
> `ansible_relay/phoenix`

## Goal

Define a local-first federation architecture that lets Ansible distribute public
content through existing open protocols without making any external protocol the
canonical product model.

The first full implementation should support direct app publication to Nostr
relays and relay-managed ActivityPub federation.

This design now treats discussion boards as Forum Host-owned surfaces. The
local app stores board projections and subscriptions; it does not treat a
local-only discussion board as the canonical collaboration object.

## Existing Context

Ansible currently stores content locally as Drift-backed domain entities. The
implemented content model includes `ContentItem` modes (`murmur`, `note`,
`post`, and `discussion`), visibility (`private`, `unlisted`, `public`), and
local-only state.

The current identity and sync path is AT Protocol-shaped: `did:plc`, XRPC-like
record creation, Ed25519 signing, and a relay that stores signed ops or Lexicon
records. That implementation is useful context, but the Rust bridge and
`did:plc` path are not yet a complete production AT Protocol identity system.

The codebase also has ActivityPub-compatible follow models in `ansible_core/ap`
and `ansible_sync/handlers`, but the Flutter app is not an ActivityPub server
and should not become one.

## Design Decision

Use Ansible's local-first domain model as the canonical model, then project to
Nostr and ActivityPub at the distribution boundary.

- Nostr is an optional federation backend and protocol baseline. The app can
  own a Nostr key and publish signed events directly to user-selected relays.
- ActivityPub is a relay responsibility. The app sends signed publication
  intents to the Ansible relay; the relay owns Actor URLs, WebFinger,
  inbox/outbox, delivery, retry, and remote federation policy.
- AT Protocol / `did:plc` remains an optional alias, compatibility path, or
  future bridge. It is not the primary public identity for the Nostr path.

This keeps the product local-first while avoiding a custom public federation
protocol.

Forum Host ownership is the board boundary:

- Forum Hosts own hosted boards, threads, posts, permissions, moderation, and
  distribution FE state.
- Local `Board` rows are projections during migration.
- `murmur` and `note` remain local canonical content and can be projected to
  selected Forum Hosts.
- Multi-host discussion distribution uses primary plus cross-post targets, not
  a shared multi-primary board identity.
- Purely local personal organization belongs to Local Collections.

Web distribution must support users who have not installed the app:

- The distribution frontend reads and writes through the Forum Host / relay API,
  not through app-local storage.
- Web users may start as hosted or passkey-authenticated accounts with lower
  trust tiers and stricter limits.
- Users who already have the app can upgrade a web session to their
  self-custody DID through an app-mediated approval flow.
- The web frontend must not receive or persist the app user's root DID private
  key.

## Identity Model

Each local account may have multiple public bindings:

- Local app identity: current DID-backed identity used by existing code.
- Nostr public identity: secp256k1 public key represented as `did:nostr` and
  user-facing `npub`.
- ActivityPub identity: relay-domain Actor URL, for example
  `https://relay.trisaura.io/users/alice`.
- NIP-05 identifier: alias such as `alice@trisaura.io`.
- AT Protocol identity: optional `did:plc` / handle alias.
- Web session identity: relay-issued browser session bound either to a hosted web
  account or to a short-lived app-signed session grant.

The canonical ActivityPub Actor must be stable under the relay domain. AT
Protocol handles and NIP-05 names can change and must not replace stored follow
targets. Nostr follows store pubkeys, not handles.

Identity strength is explicit:

- `basic_web`: hosted browser account with rate limits and moderation-first
  posting.
- `web_passkey`: browser account authenticated by WebAuthn/passkey, still treated
  as web custody unless it also has a self-custody grant.
- `self_custody_did`: app-held DID key approves the current web session. The app
  signs a short-lived grant; the browser never receives the root private key.
- `verified_human`: a DID/account with accepted VC or reputation upgrade.

## Distribution Model

The app handles local authoring, visibility, and Nostr publication. The relay
handles ActivityPub federation and web distribution frontend state.

```text
Private content:
  app local DB only

Nostr:
  app -> selected Nostr relays

ActivityPub:
  app -> signed publication intent -> relay -> ActivityPub federation

Web self-custody session:
  web -> relay challenge -> app approval/signature -> relay web session
  web -> relay/forum write API -> relay enforces session scope
```

The relay may later mirror app-authored Nostr events, but app direct publish is
the primary Nostr path.

For self-custody web use, the first supported path is app-mediated session
approval. The relay issues a login challenge, the app verifies the origin and
requested scopes, the app signs a session grant with the local DID key, and the
relay exchanges that grant for a short-lived browser session. Delegated browser
signing keys are a later extension; v1 sessions do not grant an unbounded signing
capability to the browser.

## Protocol Boundaries

The Nostr adapter must implement existing NIPs:

- NIP-01 for event envelope, event id, signing, filters, and relay messages.
- NIP-02 for follow/contact list projection.
- NIP-05 for human-readable DNS identity.
- NIP-09 for deletion request events.
- NIP-19 for user-facing identifiers.
- NIP-23 for long-form public notes.
- NIP-44 as a future encrypted payload format, not an MVP privacy boundary.
- NIP-49 for encrypted key backup/export/import.
- NIP-65 for relay list metadata.

NIP-26 delegation is intentionally excluded from v1.

The ActivityPub adapter must live on the relay side and expose the standard
server-facing surfaces: WebFinger, Actor, inbox, outbox, and delivery workers.

## Visibility And Privacy

- `private`: stays local. No Nostr event, no ActivityPub activity, no relay
  publication intent.
- `unlisted`: may be distributed, but should not be promoted in profile/index
  surfaces. This is not private.
- `public`: may be distributed to configured Nostr relays and ActivityPub.

The system must fail closed for private content. A projection layer must reject
private content before building protocol payloads.

## Failure Behavior

Nostr publish is per-relay and may partially succeed. The app should store
per-relay publication status and allow retry.

ActivityPub delivery is per-recipient or per-remote-inbox. The relay should
store delivery state and retry without requiring the app to stay online.

Deletion is best-effort externally. Local tombstones remain authoritative for
Ansible state.

## Acceptance Criteria

- New docs clearly state that the canonical model is Ansible/local-first.
- No doc claims that the app directly implements ActivityPub federation.
- NIP-26 is documented as non-MVP.
- Existing AT Protocol / `did:plc` documentation is preserved with a transition
  note, not destructively rewritten.
- The implementation plan defines a gated full federation path: publication
  abstraction first, then Nostr, then relay-managed ActivityPub.
- New board work treats Forum Hosts as the canonical owner of discussion boards
  and treats local boards as migration projections.
- New web work treats app-mediated sessions as scoped grants, not DID key export
  into browser storage.
