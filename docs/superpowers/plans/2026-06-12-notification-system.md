# Notification System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: Phase A ✅ + Phase B pipeline ✅ implemented 2026-06-13**
> (relay 246 / store 105 / app 361 tests green). Phase A is a pure local
> projection — zero new server surface; badge is a bell + unread count in
> `home/board_swipe_header.dart`, refreshed via `_loadData`; dedup keys
> `reply:<postId>`, `follower:<actorDid>`, `messenger:<messageId>`,
> `moderation:<action>:<targetRef>` (the `moderation_outcome` type landed
> with the moderation-state sync — always-on, no toggle, per Base Rule 6).
> 2026-07-22 integration hardening: existing verified replies and decrypted
> inbound messages are now rebuilt idempotently from SQLite on first app load;
> manual sync from Sync Settings uses the same projector; notification rows can
> open the live messenger conversation. Read state remains local and survives
> rebuilds.
> Phase B ships end-to-end **except platform credentials**: relay token
> registry + debounced wake scheduler (payload asserted to be exactly
> `{"hint":"sync"}`; unregister inside the debounce window cancels the
> send), app token lifecycle (`push_registration_service.dart`) + settings
> opt-in. Remaining config work (documented in
> `docs/getting-started-dev.md` § Push Notifications): an APNS/FCM
> `PushSender` adapter relay-side, a `PushTokenProvider` backed by the
> platform push plugin app-side, and the background wake handler that the
> plugin's background callback drives.

**Goal:** Users find out when something happened to them — replies to their
threads/posts, new followers, new messenger messages, moderation outcomes —
first in an in-app notification feed, then via privacy-preserving push.
Verified gap: the codebase has **zero** notification infrastructure (no
token registry, no FCM/APNS, no notification store); the only artifact is a
settings-menu label. For a social product this is the broken retention loop.

**Core insight (local-first, Design-1 style):** the app already downloads
the global op delta and the messenger mailbox. Every notification source is
therefore **already on the device** — replies reference parents the user
authored, follow ops carry the target DID, mailbox messages arrive in sync.
Phase A builds notifications as a pure **local projection** over data the
app already has: zero new server surface, zero follow-graph/attention leak.
Phase B adds content-free push wake-ups so Phase A runs when the app is
backgrounded.

## Source Context

Read first:

- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
  (Base Rule 2 governs push payloads)
- Following-feed plan (the Design-1 local-filter precedent):
  `docs/superpowers/plans/2026-06-04-following-feed-author-sync.md`

Key existing code:

- App sync (op stream the projector folds): `ansible_node/app/lib/services/remote_sync_service.dart`
- Messenger sync/mailbox: `lib/services/messenger_sync_service.dart`, relay `messenger_store.ex`
- Follow ops: `ansible_core/domain/lib/src/follow/`, relay op stream
- Drift store (new tables go here): `ansible_core/store/`
- Home shell tab bar (badge target): `ansible_node/app/lib/screens/home_shell.dart`
- Settings (notification prefs entry already labeled): `lib/screens/settings_home_screen.dart`
- Relay device-ish precedent (messenger device ids): `lib/services/messenger_device_service.dart`

---

## Constitution Review

1. **Identity/credential involved:** the user's own DID (to match ops
   referencing them) and, in Phase B, an opaque per-device push token bound
   to the DID on the relay. No credentials or legal identity.
2. **Data leaving the device:** Phase A — nothing new (projection over
   already-synced data). Phase B — the push token (explicit opt-in when
   enabling push) and **content-free** wake payloads flowing *to* the
   device. Notification content itself is never sent through APNS/FCM:
   third-party push infrastructure is outside the user's trusted boundary,
   so payloads carry at most a type hint ("sync"), satisfying Base Rule 2's
   MUST NOT (private content to external services). Messenger pushes are
   pure silent wake-ups.
3. **Minimum claim:** none.
4. **Raw legal identity excluded:** yes — tokens are opaque; relay-side push
   scheduling logs carry DID + event type only, never content.
5. **Trust/ranking/moderation change:** none. (Notification *of* moderation
   outcomes consumes the reporting plan's data; it changes visibility of an
   action already taken, not the action.)
6. **Personhood binding:** none.
7. **Exit:** per-category toggles + global off in settings; disabling push
   deletes the token from the relay (verified by test); uninstalling stops
   wake-ups by construction. Local notification rows are user-deletable and
   never leave the device.
8. **External hosts:** out of scope — Phase A/B cover the first-party relay
   path. Notifications sourced from external hosts inherit whatever sync
   path delivers their ops; no host-specific trust is added.

**Privacy property worth stating:** because Phase A is a local projection,
the relay never learns *which* notifications a user saw or cares about, and
there is no per-author query that leaks the attention graph. Phase B's wake
pushes reveal only "this DID has a device that wants wake-ups" — the
minimum possible.

**Constitution verdict:** Compliant. Content-free push payloads and
token-deletion-on-disable are mandatory elements.

---

## Design Decisions

- **Phase A before Phase B.** An in-app feed + badge delivers most of the
  retention value (next-open re-engagement) with no new server surface, and
  forces the event model to stabilize before push amplifies it.
- **Event types v1:** `reply_to_thread`, `reply_to_post`, `new_follower`,
  `messenger_message`, `moderation_outcome` (the last lands with/after the
  reporting plan). Mentions need a mention syntax first — explicitly out of
  scope.
- **Local store:** `notifications` Drift table (id, type, actor DID, target
  ref, created_at, read_at, dedup key). The projector folds during the
  existing sync passes — no separate poll loop.
- **Push transport (Phase B):** FCM (Android) + APNS (iOS) with a relay
  `device_push_tokens` table (DID, device id, token, platform, enabled
  categories). The relay schedules wake-ups when accepting ops that target
  an opted-in DID (reply/follow) and on mailbox delivery — payload is
  `{"hint": "sync"}` only.
- **Celebrity damping:** wake-up scheduling is debounced per (DID, device)
  with a short window so a burst of replies/follows sends one wake, not N
  pushes. In-app feed shows the full list regardless.
- **Badge truth is local:** unread count computed from the local table;
  relay holds no read-state (nothing to sync, nothing to leak).

**Tech stack:** Dart/Flutter + Drift + `flutter test`; Phase B adds
Elixir/Phoenix (`mix test`) + platform push setup (APNS key, FCM project).

---

## Task 1: Local notification store + projector (Phase A)

- [x] Drift table + repository in `ansible_core/store` with dedup-key upsert
      (re-synced ops must not duplicate notifications).
- [x] Projector folds during op sync: replies where the parent
      thread/post author is the local DID (self-replies excluded); follow ops
      targeting the local DID.
- [x] Messenger sync emits `messenger_message` notifications for non-blocked
      contacts (reusing existing block/trust checks).
- [x] Unit tests: each type, dedup on re-sync, self-action exclusion,
      blocked-contact exclusion.

## Task 2: Notification UI (Phase A)

- [x] Notification feed screen (actor, type label zh/en, target preview,
      relative time); tap navigates to thread/post/profile/conversation;
      mark-read on view + mark-all-read.
- [x] Unread badge on the home shell tab bar driven by the local count.
- [x] Settings: per-category toggles (feeding both the projector and, later,
      push categories) replacing the placeholder label.
- [x] Widget tests: feed render, navigation per type, badge count, toggles.

## Task 3: Relay — push token registry + wake scheduling (Phase B)

- [x] `device_push_tokens` table + authenticated register/unregister
      endpoints (disable deletes the row — tested).
- [x] Wake scheduler: on accepting a reply/follow op targeting an opted-in
      DID and on mailbox delivery, enqueue a debounced content-free push;
      respects per-category opt-outs.
- [x] Payloads are `{"hint": "sync"}` — a test asserts no content fields can
      appear.
- [x] Tests: scheduling per type, debounce window, opt-out respected,
      unregister stops sends.

## Task 4: App — push wiring (Phase B)

- [x] Token registration with the relay: `push_registration_service.dart`
      (signed canonical payloads, stable per-install device id, register
      returns false when no platform token exists) + settings opt-in that
      only prompts/registers when the user enables push (never at first
      launch). Permission prompt + token **rotation** land with the platform
      plugin below.
- [x] APNS token provider (2026-07-03): `ApnsPushTokenProvider` over a native
      `elix/push_token` channel (AppDelegate) — no Firebase dependency;
      `aps-environment` entitlement + `remote-notification` background mode
      added; wake handler seam is `onWake` (fires while the engine is alive).
      Remaining: FCM provider for Android (with the Android release work) and
      cold-start background execution.
- [x] Platform config steps documented in `docs/getting-started-dev.md`
      (§ Push Notifications).
- [x] Tests: token lifecycle (mockable signer/provider/client), settings
      toggle register/unregister, hidden-without-context state. Wake-handler
      tests land with the plugin integration above.

## Task 5: Docs + status

- [x] README component table row for notifications; `docs/ROADMAP.md`
      Product Track row updated; architecture plan's Phase 3 note that op
      firehose later replaces poll-on-wake.

## Task 6: Local Projection Integration Hardening

- [x] Backfill verified replies and successfully decrypted inbound messages
      from existing SQLite state using the same stable dedup keys.
- [x] Preserve read state during every backfill and exclude unverified local
      rows from becoming trusted notifications.
- [x] Run the notification projector for manual Sync Settings pulls as well as
      the home/background sync path.
- [x] Pass the messenger service into the navigation tab so message
      notifications open their local conversation.

## Definition of Done

- Phase A: with two test accounts, a reply / a follow / a message each
  produce exactly one notification on the recipient's device after sync;
  badge counts unread; re-sync never duplicates; nothing about notifications
  appears in any server request.
- Phase B: with the app backgrounded, the same events produce a single
  content-free push wake and a locally-composed notification; disabling push
  removes the token server-side.
- `make test-app test-relay` green; `flutter analyze` clean.
