# User-Controlled Fediverse Preferences

> Date: 2026-07-26
> Status: Implemented design
> Scope: Wallet/App, Relay, ActivityPub actor exposure and delivery

## Decision

ActivityPub federation is an explicit, reversible user distribution path.
Reaching `verified_human` never exposes an actor by itself, and publishing a
first Note no longer implicitly enables federation.

The App submits a DID-signed preference document containing:

- `enabled`
- `default_note_visibility` (`public` or `unlisted`)
- `allow_remote_followers`
- `domain_policy` (`open` or `allowlist`)
- `allowed_domains`
- `blocked_domains`
- `blocked_actors`
- a monotonically increasing `revision`

Only a currently `verified_human` account may change `enabled` from false to
true. Disabling remains available after credential expiry or trust downgrade so
the user never loses the ability to exit.

Each Note independently selects local-only, Nostr, ActivityPub, or both.
ActivityPub publication additionally requires the stored preference to be
enabled. Private content remains ineligible.

## Federation Scope

Federation is account-driven rather than a fixed list of supported products or
servers. Remote followers dynamically determine delivery recipients. Policy is
applied in this order:

1. platform blocked domains (mandatory security/legal boundary);
2. user blocked actors;
3. user blocked domains;
4. optional user allowlist mode.

The user allowlist is an advanced privacy mode. In normal `open` mode, any
non-blocked remote host may interoperate. Policy applies to both remote actor
URLs and resolved inbox URLs.

## Disable Semantics

Disabling immediately:

- hides WebFinger, Actor, Inbox, Outbox, and followers endpoints;
- rejects new ActivityPub publication intents;
- stops creating new delivery attempts.

Existing immutable publication records remain for audit and retry safety.
Sending ActivityPub `Delete` activities to existing followers is a follow-up
because it requires authenticated inbound federation and a durable account
deletion ceremony. The UI describes the current action as “pause/disable”, not
remote erasure.

## Constitution Review

1. Identity: the user-held DID key signs every preference revision.
2. Data leaving the device: only federation settings and explicitly selected
   public/unlisted Notes.
3. Minimum claim: Relay checks only the `verified_human` tier; no nationality,
   age, credential ID, or legal identity enters ActivityPub.
4. Raw identity, provider assertions, private keys, and personhood commitments
   are excluded.
5. Enabling changes distribution access with explicit reason codes.
6. No new personhood binding is created.
7. Users can disable at any trust tier and can block actors/domains.
8. External hosts remain `unknown` unless separately evaluated; allowlisting a
   host does not claim constitution compliance.

