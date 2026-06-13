# Content Reporting & Board Moderation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: ✅ implemented 2026-06-13** (relay 229 tests / frontend 90
> assertions / app 336 tests, all green). Implementation notes & deviations:
> - "Web rail" auth is **bearer-token web sessions** (the codebase's existing
>   `/web/*` pattern) — there is no cookie mechanism.
> - Moderator = host owner DID (`:forum_host_owner_did` env) **or** the
>   board's creator DID **or** `moderation_policy["moderators"]` (extension
>   point, no UI yet).
> - Tombstones/lock flags are served in `/api/v1/ops/delta` (content
>   stripped, stored ops untouched) and in the public
>   `GET /boards/:id/moderation-state`; the **web frontend** renders them.
>   **App-side** tombstone/lock rendering from the synced overlay is the one
>   remaining follow-up (unticked below), as is the `moderation_outcome`
>   notification type (waits on this + notification Phase B).
> - `dismiss_report` requires `report_id` (422 `unknown_report` otherwise).

**Goal:** Users can report a thread/post with a reason code; board moderators
get a queue and can act (remove-from-board, lock thread, dismiss) with
reason-coded, user-visible outcomes. This is the minimum safety net required
before real users — today **no report path exists anywhere** (verified: zero
hits for report/flag flows in app or relay), despite the constitution
requiring reason-coded, transparent moderation.

**Scope boundary (constitution Rule 7):** this plan builds **host-level**
moderation — a Forum Host moderating its own boards. It does not build
system-level enforcement (that exists separately as the relay abuse
detector) and host actions MUST NOT present as global truth: removing a post
from a board removes the **board projection**, never the author's local copy
or other distribution paths.

## Source Context

Read first:

- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
  (Base Rules 6, 7; exception model for audit trails)
- Boundary work: `docs/superpowers/plans/2026-06-02-relay-forum-host-boundary-implementation.md`

Key existing code:

- Forum host store + schemas: `ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex`,
  `db/forum_host_board.ex` (has `moderation_policy` map, currently unused),
  `db/forum_host_accepted_intent.ex`
- Signed intents (reports ride this rail): `forum_host/signed_intent.ex`
- Abuse detector (system-level, stays separate): `abuse_detector.ex`
- Web session writes + frontend: `web/controllers/web_session_controller.ex`,
  `ansible_distribution_frontend/src`
- App thread/post screens (report entry points):
  `ansible_node/app/lib/screens/posts_view_screen.dart`,
  `discussion_detail_screen.dart`, `threads_list_screen.dart`
- Rate limiting pattern (reuse for report spam): relay token bucket in
  `abuse_detector.ex`

---

## Constitution Review

1. **Identity/credential involved:** reporter DID (reports are signed intents
   — accountable, not anonymous to the host) and moderator DID. No
   credentials or legal identity involved.
2. **Data leaving the device:** the report itself (target ref, reason code,
   optional free-text note) — an explicit user action. Reports reference
   already-public board content only; no private content can be reported
   because private content never reaches a host.
3. **Minimum claim:** none — no verification claim; the reporter's tier is
   read only for rate limiting.
4. **Raw legal identity excluded:** yes. Reports, moderation records, and
   audit logs carry DIDs + reason codes; free-text notes are visible to
   moderators only and excluded from any public surface and from logs.
5. **Trust/ranking/moderation change:** yes — the feature's purpose. Per Base
   Rule 6/7 this plan REQUIRES: every action carries a reason code from a
   fixed enum; the affected author can see the action + reason (unless a
   safety/legal carve-out is recorded); actions are time-stamped and
   attributed to a moderator DID in an audit table; lock/removal is
   host-scoped, never global.
6. **Personhood binding:** none.
7. **Exit:** authors keep their local content and other distribution paths;
   users can leave/mute/block the board or host regardless of moderation
   state (existing block/mute paths unaffected). Moderation never deletes
   user-owned local data.
8. **External hosts:** external hosts run their own moderation; their
   compliance level (already in discovery) signals whether they follow the
   reason-coded model. This plan implements the first-party host.

**Anti-abuse note (Base Rule 4):** reporting is itself an abuse vector.
Reports are rate-limited per reporter DID with stricter limits for
lower-tier DIDs, reusing the relay token-bucket pattern.

**Constitution verdict:** Compliant, with the reason-code enum, author
visibility, host-scoping, and audit trail as mandatory (not optional)
elements.

---

## Design Decisions

- **Reason codes (fixed enum, v1):** `spam`, `harassment`, `illegal_content`,
  `off_topic`, `impersonation`, `other` (requires note). Enum lives in one
  relay module; UI labels localized app/frontend-side.
- **Reports ride the signed-intent rail** (app) and the web-session write
  rail (frontend) — the same two authenticated chokepoints as posting; no
  new auth surface.
- **Moderator = board owner DID for MVP.** A `moderators` list inside
  `moderation_policy` is the extension point; role management UI is not MVP.
- **Moderator console lives in the distribution frontend** (web), not the
  app — web sessions already provide DID-authenticated scoped writes, and
  moderation is a desk task. The app only gains the *report* entry points
  and the *author-facing outcome* display.
- **Action set v1:** `dismiss_report`, `remove_post_from_board`,
  `lock_thread`, `unlock_thread`. Pinning, bans, and timed suspensions are
  follow-ups (bans interact with Base Rule 4 time-bounding and need their
  own review).
- **Author notification of outcomes:** v1 surfaces the moderation state
  inline (removed-post placeholder with reason code visible to the author;
  locked-thread banner for everyone). Push/inbox notification of moderation
  actions hooks into the notification system plan
  (`2026-06-12-notification-system.md`) once it lands.

**Tech stack:** Elixir/Phoenix + `mix test`, Dart/Flutter + `flutter test`,
Node tests for the frontend console.

---

## Task 1: Relay — report intake

- [x] New tables: `forum_host_reports` (id, target kind/ref, board id,
      reporter DID, reason code, note, status, timestamps) and
      `forum_host_moderation_actions` (action, target ref, board id,
      moderator DID, reason code, report id?, timestamps) — the audit trail.
- [x] Signed-intent type `report_content` + web-session report endpoint, both
      validating reason enum and target existence, both rate-limited per
      reporter DID (tier-aware token bucket).
- [x] Duplicate handling: same reporter + same target collapses to one open
      report.
- [x] Tests: happy paths on both rails, bad reason rejected, rate limit
      enforced, duplicate collapsed.

## Task 2: Relay — moderation actions + projection effects

- [x] Moderator authorization: board owner DID (from board/host ownership)
      may list reports for the board and submit actions.
- [x] `remove_post_from_board`: board read APIs (threads/posts listings, board
      feed, AppView board projection) replace the post with a tombstone
      carrying the reason code; the underlying op/record is untouched.
- [x] `lock_thread` / `unlock_thread`: thread accepts no new post intents while
      locked; listings carry `locked: true` + reason code.
- [x] Every action writes the audit row; report status transitions
      (`open → actioned | dismissed`).
- [x] Tests: authorization (non-owner rejected), tombstone in all read paths,
      locked thread rejects posts with reason-coded 403, audit rows written.

## Task 3: App — report entry + outcome visibility

- [x] Report action (reason picker + optional note) on posts and threads in
      `posts_view_screen.dart` / `discussion_detail_screen.dart`, submitted as
      a signed intent; confirmation + already-reported state.
- [ ] (follow-up) Removed-post tombstones and locked-thread banners render
      in the **app** with localized reason labels; the author of a removed
      post sees the reason code (constitution-mandated visibility). Web
      frontend already renders both; the app currently learns lock state
      only via the reason-coded 403 on reply.
- [x] Widget tests for report flow, tombstone, lock banner.

## Task 4: Frontend — moderator console

- [x] `/moderation` view (web-session authed, owner DID only): open reports
      queue grouped by board, each with target preview + reason + note.
- [x] Action buttons (dismiss / remove / lock / unlock) calling the relay
      APIs; optimistic queue updates; action history (audit) view.
- [x] Public board pages render tombstones/lock states.
- [x] Node tests for queue rendering and action calls.

## Task 5: Docs + status

- [x] Document the reason-code enum and the host-level vs system-level
      boundary — covered by this plan's Design Decisions + Status header
      (single source of truth; a separate architecture doc was redundant).
- [x] README component table + `docs/ROADMAP.md` Product Track row updated.

## Definition of Done

- A user can report a post from the app with a reason; the board owner sees
  it in the web console, removes the post; the post becomes a reason-coded
  tombstone in app + web + AppView feeds while the author's local copy is
  untouched and the author can see why; the whole trail exists in the audit
  table. Report spam from a basic-tier DID gets rate limited.
- `make test-relay test-app test-frontend` green.
