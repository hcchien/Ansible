# Trust-Gated Boards（真人驗證版）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a board owner require a minimum reputation tier to **post** in a
hosted board — the flagship use case being「只有驗證過的真人能發文」boards.
This turns the existing VC → reputation-tier pipeline into a user-visible
product feature instead of just a profile badge.

**Core insight:** Every piece of the pipeline already exists. Boards have a
`posting_policy` map field that is empty today
(`ansible_relay/.../db/forum_host_board.ex`), DID accounts carry
`reputation_tier` (default `"basic"`,
`ansible_relay/.../db/did_account.ex:10`), tiers propagate relay → AppView →
app badges, and all posting goes through two relay-enforced chokepoints
(signed intents from the app; cookie web sessions from the frontend). The MVP
is wiring a `min_post_tier` key through those chokepoints and the UI.

## Source Context

Read first:

- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
  (Base Rules 4, 5, 6, 7 govern this feature)
- Boundary work: `docs/superpowers/plans/2026-06-02-relay-forum-host-boundary-implementation.md`

Key existing code:

- Board schema with empty `posting_policy`: `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_board.ex`
- Board store / creation: `ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex` (`create_board/1`, `list_boards/0`)
- Signed intent validation: `ansible_relay/phoenix/lib/ansible_relay/forum_host/signed_intent.ex`
- Tier source: `ansible_relay/phoenix/lib/ansible_relay/did_account_cache.ex`, `db/did_account.ex` (`reputation_tier`)
- Forum host API: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`
- Web session scoped writes: `web/controllers/web_session_controller.ex`, `web_session_store.ex`
- App board creation/browse: `ansible_node/app/lib/widgets/board_form_dialog.dart`, `lib/screens/boards_list_screen.dart`, `lib/screens/discover_screen.dart` (board rows)
- App credential wizard (the "upgrade tier" path): `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Frontend board views: `ansible_distribution_frontend/src`

---

## Constitution Review

1. **Identity/credential involved:** the poster's DID and its relay-side
   `reputation_tier`. The gate reads the **tier label only** — never the
   underlying VC, personhood commitment, or any legal-identity field.
2. **Data leaving the device:** none new. Posting already sends signed intents
   to the relay; the gate is a server-side check on data the relay already
   holds.
3. **Minimum claim:** the tier (`basic` / `verified_human`) is exactly the
   minimum claim for the decision "may this DID post here" (Base Rule 3).
4. **Raw legal identity excluded:** yes — tier is an opaque label; rejection
   responses and logs carry DID + reason code only.
5. **Trust/ranking/access change:** yes, by design — and it is **reason-coded**
   (`posting_requires_tier`) and **host-level**, not system-level. The board's
   requirement MUST be discoverable before posting (Base Rule 6) and the
   rejection MUST tell the user what tier is needed and how to get it
   (Base Rule 4: stricter limits on lower-trust identities, transparently).
6. **Personhood binding:** none created; this consumes the existing tier.
7. **Exit / lower-trust path:** gating applies **per board, by host choice,
   to posting only**. Reading stays open per the board's existing visibility.
   Ungated boards remain the default (`posting_policy` empty ⇒ no gate), so
   ordinary use never requires high-assurance verification (Base Rule 5
   MUST NOT). A host raising the gate does not retroactively remove existing
   posts.
8. **External hosts:** an external Forum Host may declare any
   `min_post_tier`; the app trusts the **first-party relay's** tier mapping
   when composing, and external hosts' compliance level (already exposed in
   discovery) tells users whether the gate is meaningfully enforced.

**Constitution verdict:** Compliant — this is the textbook Base Rule 6 case
("Forum Hosts define board-level posting permissions and trust
requirements"). The mandatory pieces are: reason-coded rejection, gate
discoverable before posting, posting-only scope, and ungated default.

---

## Design Decisions

- **Policy shape:** `posting_policy["min_post_tier"]: "basic" | "verified_human"`
  (absent ⇒ no gate). Single key, extensible map already exists — no
  migration needed for the schema itself.
- **Enforcement point: relay, at intent acceptance.** Both write paths
  (signed intents, web-session writes) already terminate in the relay, which
  also owns the tier cache. Client-side checks are UX sugar only; the relay
  check is authoritative. Tier is read at **acceptance time** (no caching of
  the decision), so revocation/expiry takes effect immediately.
- **Thread creation and replies are both gated** by the same key in MVP. A
  separate `min_thread_tier` (e.g. anyone replies, only verified humans open
  threads) is a follow-up, not MVP.
- **Reads are never gated** by this feature. Read access control is a
  different concern (board visibility) and stays out of scope.
- **Rejection contract:** HTTP 403 with
  `{"error": "posting_requires_tier", "required_tier": ..., "current_tier": ...}`
  so both app and frontend can render the upgrade path.

**Tech stack:** Elixir/Phoenix + `mix test` (relay), Dart/Flutter +
`flutter test` (app), Node test runner (frontend).

---

## Task 1: Relay — policy validation + gate at both write chokepoints

- [ ] `forum_host/store.ex` `create_board/1` (and board update path) validates
      `posting_policy["min_post_tier"]` against the allowed tier enum; rejects
      unknown values.
- [ ] Signed-intent acceptance for thread/post creation resolves the author
      DID's `reputation_tier` via `did_account_cache` and rejects with the
      reason-coded 403 contract when below `min_post_tier`.
- [ ] Web-session scoped write path applies the identical check (no bypass via
      cookie writes).
- [ ] Tier ordering helper (`basic < verified_human`) lives in one module used
      by both paths.
- [ ] Tests: ungated board unchanged; gated board rejects `basic` and accepts
      `verified_human` on both paths; rejection body matches the contract;
      unknown tier value in policy rejected at board create.

## Task 2: Relay — expose the gate in discovery and board APIs

- [ ] `min_post_tier` included in board listings, board search results, and
      host info responses (it already serializes via the `posting_policy`
      field — verify and add explicit tests so it never regresses).
- [ ] AppView board-feed / board search projections carry the policy through
      unchanged.

## Task 3: App — set the gate at creation, show it before posting

- [ ] `board_form_dialog.dart`: host-side option「發文資格」(不限 /
      真人驗證) writes `posting_policy.min_post_tier` into the create-board
      intent.
- [ ] Board rows (boards list, discover search results, board header) show a
      gate badge（「真人版」）when `min_post_tier == verified_human`.
- [ ] Compose entry points check the local tier badge state: below-tier users
      see the composer disabled with an explanation and a button into
      `credential_issuance_wizard.dart`（升級驗證）— gate discoverable
      **before** writing, per the constitution review.
- [ ] Server 403 `posting_requires_tier` is mapped to the same friendly
      message (the relay remains authoritative; the client check is UX only).
- [ ] Widget tests for: badge rendering, disabled composer + upgrade CTA,
      403 mapping.

## Task 4: Frontend — display + block

- [ ] Board pages render the gate badge and requirement text.
- [ ] Web-session write UI hides/disables posting for sessions whose DID tier
      is below the gate, with the same upgrade messaging (pointing back to
      the app).
- [ ] Node tests for both states.

## Task 5: Docs + status

- [ ] README component table: Reputation Labeler row notes tiers now gate
      posting per board.
- [ ] `docs/ROADMAP.md` Product Track row → Done with link here.

## Definition of Done

- A host can create a verified-human-only board from the app.
- A `basic` DID sees the requirement before composing, cannot post via app
  or web session, and gets a working upgrade path; after completing
  verification (tier flips to `verified_human`), posting succeeds without
  re-login.
- All relay/app/frontend suites green: `make test-relay test-app test-frontend`.
