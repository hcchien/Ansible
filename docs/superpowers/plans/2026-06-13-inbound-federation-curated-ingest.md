# Inbound Federation — Curated ActivityPub Ingest（站外內容引入）

> Status: **Design for review** — settles how foreign ActivityPub content
> enters Elix without breaking the trust model or the Phase 2 integrity
> guarantees. Per AGENTS.md this design + its constitution review is the
> required gate before any inbound-federation implementation.
> Date: 2026-06-13

**Goal.** Let real content from the wider fediverse appear in Elix so the
network isn't empty at launch — **without** diluting the wedge (真人驗證 /
bot-free Taiwanese discussion), violating the constitution, or
contaminating the verified, trust-gated surfaces we just built.

**What exists today.** ActivityPub support is **outbound projection only**
(relay actor/WebFinger/outbox/retry, partial). There is no inbound path:
no inbox endpoint, no remote-actor resolution, no way for foreign posts to
reach the AppView. This design adds a **bounded, pull-based, clearly-
labeled** inbound lane — explicitly NOT an open firehose.

## Source Context

Read first:
- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
  (Base Rules 1, 4, 6, 7 + the external-host compliance-level model — all bind here)
- Federation strategy: `docs/protocol/tris_aura_federation_strategy_v0.1.md`
  (Nostr/AP are projections, never the canonical store)
- Phase 2 verification we must not contaminate:
  `ansible_appview/phoenix/lib/ansible_appview/ingest/folder.ex`,
  `db/feed_item.ex` (`sig_verified`, `source`, `author_tier`),
  `lib/ansible_appview/timeline.ex` + `discovery.ex` (public reads require
  `sig_verified == true`)
- Existing AP code (outbound): `ansible_relay/phoenix/lib/ansible_relay/activity_pub/`

## The core problem this design solves

The Phase 2 work made every public AppView read require `sig_verified ==
true` — an Ed25519 signature over an Elix op by a known DID. **Foreign AP
content has no Elix op and no Elix signature.** So inbound content cannot
and must not pretend to be verified Elix content. The design's whole job is
to give it a **separate, honestly-labeled lane** that:
- never sets `sig_verified = true`,
- never appears on verified/trust-gated/真人版 surfaces,
- carries a visible external origin + compliance level,
- can be switched off (drop the actor → content gone), and
- is bounded so T&S and legal exposure stay manageable.

---

## Constitution Review

1. **Identity/credential:** remote AP actors (actor URI + instance). Never
   conflated with an Elix DID; never granted an Elix reputation tier.
2. **Data in/out:** ingests **public** AP content only (public outbox
   posts of curated actors). No private content in or out. No Elix user
   data is sent to remote servers by ingest.
3. **Minimum claim:** none — external content makes no verification claim;
   it is displayed *as* external.
4. **Raw legal identity:** none involved.
5. **Trust/ranking change — the load-bearing rule:** external actors map to
   a fixed tier `external_unverified` with `compliance_level` (`compatible`
   for allowlisted instances we've assessed, else `unknown`). They are
   **excluded** from: trust-gated/真人版 boards, who-to-follow
   recommendations of "verified" people, and any ranking that implies Elix
   trust. The external origin + compliance level MUST be visible wherever
   the content shows (Base Rule 6/7; external-host compliance model).
6. **Personhood binding:** none; ingest never creates or consumes a
   nullifier. External content can never satisfy a personhood requirement.
7. **Exit/reversibility:** removing an actor/instance from the allowlist
   removes its content from Elix surfaces (tested). Users can mute external
   content entirely (a single toggle). Moderation can tombstone individual
   external items host-side, same as native content.
8. **External hosts:** this *is* the external-host case. Compliance level is
   assessed per allowlisted instance and surfaced; un-assessed sources stay
   `unknown` and lower-ranked.

**Verdict:** Compliant **only** in the curated + labeled + no-trust +
reversible shape below. An open inbound firehose, or mixing external
content into verified surfaces, would violate Base Rules 4/6/7 and is out
of scope.

---

## Design Decisions

- **D1 — Curated allowlist, NOT open firehose (v1).** An admin-curated set
  of remote actors (and/or instances) we choose — ideally on-wedge
  (Taiwanese fediverse accounts). Rationale: bounded T&S, on-brand
  curation, constitution-safe. Open discovery/firehose is deferred and may
  never be appropriate.
- **D2 — Pull, not push (v1).** Poll the curated actors' public outboxes on
  an interval and verify the fetch with HTTP signatures where available. NO
  inbound `/inbox` endpoint in v1 — that's an unbounded spam/abuse attack
  surface. (Inbox push is a later, separate decision.)
- **D3 — Separate provenance lane in the AppView.** Ingested items become
  `feed_items` with `source = "activitypub"`, `sig_verified = false`,
  `author_tier = "external_unverified"`, plus new columns
  `external_actor_uri`, `external_instance`, `compliance_level`. The Phase
  2 read filter (`sig_verified == true`) keeps them OUT of the default
  verified feed by construction — they surface ONLY through an explicit
  external query path (see D4). HTTP-signature validity is recorded but is
  transport auth, never Elix identity.
- **D4 — Surfaced behind an explicit, labeled boundary.** Not in the
  default following/home feed. A distinct「站外 / External」surface (a tab or
  an opt-in per-board inclusion) renders external items with an unmistakable
  origin badge (instance + actor) and compliance label. Default is
  off/separate; the user opts in to seeing external content.
- **D5 — Moderation + reversibility.** Allowlist is the primary filter;
  per-actor/per-instance removal drops content; the existing host
  moderation can tombstone individual external items. A global "hide all
  external" user toggle.
- **D6 — No outbound interaction coupling in v1.** Replying to / following
  external actors from Elix (true two-way federation) is a separate, harder
  step (delivery, threading, identity). v1 is read-in only.

What v1 explicitly is NOT: an open firehose, an inbox endpoint, two-way
interaction, external content on verified/真人版 surfaces, or any path that
raises a remote actor's Elix trust.

---

## Implementation Task Outline

- [ ] **Task 1 (relay or appview — decide owner):** curated-source registry
      (allowlist of actor URIs / instances + assessed compliance_level),
      admin-managed; config + table.
- [ ] **Task 2 (ingest):** a poller that fetches each allowlisted actor's
      public outbox, validates HTTP signatures, normalizes AP Note → an
      internal external-item shape, dedups by AP object id.
- [ ] **Task 3 (AppView read model):** `feed_items` columns
      (`external_actor_uri`, `external_instance`, `compliance_level`) +
      ingest path that writes `source=activitypub`, `sig_verified=false`,
      `author_tier=external_unverified`; **a regression test that an
      external item never appears in the verified timeline/discovery reads.**
- [ ] **Task 4 (external read API + app/frontend surface):** an explicit
      external-content query; app + frontend「站外」surface with origin +
      compliance badge and the global hide toggle.
- [ ] **Task 5 (moderation + reversibility):** allowlist removal drops
      content; per-item tombstone; tests for the exit paths.
- [ ] **Task 6:** metrics (external_ingest_total{instance}, dedup hits),
      docs, and a compliance-review note.

## Open decisions for the owner (content/policy, not engineering)

1. **Allowlist scope:** which instances/actors seed v1? (On-wedge Taiwanese
   fediverse accounts give the most value; generic global content gives the
   least and the most noise.)
2. **Surfacing default:** is external content a separate「站外」tab the user
   visits, or opt-in inclusion per board? (Recommend: separate tab, off by
   default in the main feed — keeps the wedge clean.)
3. **Compliance assessment:** who assesses an instance's compliance level
   before it's allowlisted as `compatible` vs left `unknown`?

## Definition of Done (for this design)

- D1–D6 reviewed/accepted (or amended) by the owner, and the three
  content/policy decisions above answered.
- Constitution review accepted; the "external never on verified surfaces"
  property is the non-negotiable invariant the implementation must test.
- Implementation plan(s) drawn from the task outline.
