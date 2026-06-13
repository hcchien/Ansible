# PM Product Review — Ansible / Tris-Aura (Elix)

> Author: Product review (PM)
> Date: 2026-06-13
> Inputs: README.md, docs/ROADMAP.md (Product Track), service_architecture_plan.md,
> the engineering constitution + compliance review, the superpowers plans/specs
> index, and `git log` for the last ~6 weeks.
> Scope: positioning, roadmap order, launch readiness, retention/growth, risk,
> metrics, and the next three things to ship. Strategy only — no code changed.

---

## Executive summary

Ansible/Elix is a local-first, pseudonymous-but-Sybil-resistant forum with a
self-sovereign identity stack, aimed at Taiwan. The thesis is sharp and defensible:
**「沒有機器人、沒有真名、內容永遠是你的討論區」** — a place where a board can require a
verified *human* (not a verified *name*) to post, enforced cryptographically at the
relay, with the constitution forbidding real-name defaults (Base Rule 1), mandating
data autonomy and fail-closed privacy (Base Rule 2), and minimal-disclosure
verification (Base Rule 3). The flagship feature that makes this real — trust-gated
boards（真人驗證版）— shipped this week, alongside content reporting/moderation and a
content-free notification pipeline. The engineering foundation is genuinely ahead of
most pre-launch products.

The single most important strategic call: **the product is now blocked not by
engineering depth but by the absence of a network. Day-one Elix is a ghost town with
no seed content, no genesis boards, no way to share a thread out to LINE/Threads, and
no way to know whether anything is working.** Stop adding identity/federation surface
area and spend the next cycle on cold-start seeding, an outbound sharing loop (OG +
deep links), and constitution-compatible activation metrics. Recovery (the one true
launch-blocking *foundation* gap) is designed and should be implemented in parallel,
but it is necessary-not-sufficient: an unrecoverable account in an empty forum still
fails.

---

## Positioning & wedge analysis

**Who is the user?** Privacy-aware Taiwanese forum participants who are tired of two
failure modes: (1) bot/agency-farmed manipulation and astroturfing (the PTT/Dcard
trust-erosion problem), and (2) platform capture of identity and content (the
Threads/Meta and Dcard-account-lock problem). The early-adopter wedge is narrower:
communities that *care enough about authenticity to want a human-only board* —
issue-based discussion, local civic/community groups, hobby communities plagued by
spam/scalpers.

**What is the wedge?** Trust-gated boards（真人驗證版）. This is the one feature no
incumbent can copy without abandoning their model:

- **PTT** has pseudonymity and culture but its anti-bot story is account-age/IP
  heuristics, not personhood; identity is server-owned.
- **Dcard** uses school-email gating — that is real-name-adjacent and exclusionary,
  and identity/content are platform-owned.
- **Threads/Bluesky** optimize for reach and real-ish identity; Bluesky's AT Proto is
  portable but has no personhood layer and no privacy-preserving Sybil resistance.

Elix's differentiator is the *combination*: **verified-human gating WITHOUT
real-name, with minimal-disclosure VCs and a nullifier-based uniqueness key that never
enters the post or the verifier presentation** (Base Rule 5; `national_id_hash` stays
inside the issuer boundary). That is a position none of the four incumbents occupy.

**Is the angle right? Yes — with one caveat.** The 真人驗證 wedge is correct and
should be the headline. The caveat is that the verification supply chain is not yet
production-real: the TW provider production adapter and MobileMoica RP config are both
fail-closed pending external partner integration (ROADMAP "Next"). So at soft launch,
"verified human" will be backed by passport-NFC personhood and whatever lower-assurance
paths exist, not the TW digital-identity flow that the marketing implies. **Positioning
must not over-promise the TW-government-grade path until that adapter is live.** Lead
with "human-verified boards" and the data-autonomy promise; treat MOICA as a roadmap
proof point, not a launch claim.

**Coherence of the feature set.** The shipped loop is coherent: identity → post →
report/moderate → notify → return. The *incoherence* is that the federation surface
(AT Proto legacy, Nostr partial, ActivityPub partial) is broad but half-finished and
adds zero value to the Taiwan wedge at launch. The roadmap already makes the right
call (Freeze AT/PLC, cut extra locales, contain messenger) — that instinct should be
pushed harder.

---

## Roadmap critique

| Item | Current priority | PM's recommended priority | Rationale |
|---|---|---|---|
| Cold-start strategy (genesis boards, default follows, seed content) | P2 (no plan, "operations not engineering") | **P0 — launch blocker** | Discover/feed/search are all built and serve an empty set on day one. No seeding = no first session worth having. This is the highest-leverage missing piece and it has no plan file. Needs a named owner now. |
| Sharing & deep links (OG tags, share sheet, universal links) | P2 | **P1** | Verified absent — grep found no `og:` tags and only incidental `app_links` build artifacts. The forum growth loop (thread → LINE/Threads → visit → register) is physically impossible today. Cheapest growth lever in the repo. |
| Privacy-preserving product metrics | P2 | **P1** | Without activation/retention aggregates, every prioritization above is a guess. Constitution-constrained but solvable (see metrics section). Should land before, not after, the soft launch it is meant to measure. |
| Identity recovery & re-anchor implementation | P1 / "Now", design v1.1 written | **P0 — launch blocker (keep)** | Correct. Device loss = permanent identity loss today (G14). Design is done and well-scoped (hardware-deferred, all-Ed25519, 72h veto). Implement now. The only foundation gap that is genuinely launch-blocking. |
| Hardware key custody deferral | Later (P3, deferred 2026-06-13) | **Endorse the deferral** | Right call. Secure Enclave onboarding friction would kill activation; custody-class labeling + reduced-trust mode satisfies Base Rule 1's explicit alternative. Returns later as opt-in, zero protocol change. |
| Observability baseline (Phase 0) | P1, still open | **P1 (keep, scope tightly)** | Needed, but scope to the handful of series that gate launch decisions and feed the metrics proposal — not a full PromEx build-out. |
| Data-plane integrity (Phase 2: AppView re-verify, ops partitioning) | P2 / "Next" | **P2 (keep) — but pull AppView signature re-verification forward to P1** | Ops partitioning is genuinely "before meaningful traffic" (not soft launch). But AppView trusting the relay's signature check (G4) is a trust-model hole that undercuts the entire "independently verifiable" pitch; the re-verification slice is cheap and on-message. |
| TW provider production adapter / MobileMoica RP | P1 / "Next" | **P1 (keep) — but it is partner-blocked, so de-risk positioning, not the schedule** | Cannot be scheduled (external dependency). The product response is positioning discipline, not engineering effort. |
| Federation completion (Nostr custody, ActivityPub inbox) | Later (P3) | **Later (keep) / lean toward Freeze for launch** | Half-finished adapters add risk and zero wedge value at launch. Finish only the projection paths that already work; do not invest in inbound AP behaviors pre-launch. |
| Messenger expansion | Freeze/contain | **Endorse the contain** | E2E 1:1 is a separate product. Right to cap it. |
| Android release readiness | P2, stalled | **P2 (keep), but pick ONE platform for soft launch** | Effort has gone to iOS. Do not split a tiny team across two stores for a soft launch — ship iOS *or* Android, finish it, learn, then port. |

**Over-invested (gold-plating relative to launch value):** the federation breadth (AT
Proto/PLC legacy bridge, partial ActivityPub, partial Nostr), the AppView Phase C
fan-out-on-write home timeline with celebrity-hybrid + cold-reader fallback (a
scale-out solution for a network that has no users yet), and the six extra locales the
roadmap already flagged for cut. The scalable-feed work is excellent engineering aimed
at a problem the product does not have at soft-launch volume.

**Under-invested:** everything in the growth/measurement column — cold start, sharing,
metrics, and the value-prop copy rewrite (mechanism→benefit). These are the cheapest,
highest-leverage items and they have the least investment.

---

## Launch-readiness gap analysis

Cross-checked against README MVP/partial markers and the architecture gap inventory.

| Gap | Severity | Owner area | Notes |
|---|---|---|---|
| No cold-start seeding (genesis boards, default subscriptions, seed content) | **Launch-blocking** | Product/Ops | Discover/feed/search all built (README ✅ MVP) but serve empty results. No plan file exists. Single biggest day-one risk. |
| Identity recovery not implemented (only design exists) | **Launch-blocking** | App / Rust core / Relay (Phase 1) | G14. Device loss = permanent identity + content loss. Design v1.1 is solid; implementation is the gate. |
| No outbound sharing loop (OG meta, share sheet, universal/deep links) | **Launch-blocking** for growth | Frontend + App | Verified absent. Without it there is no organic acquisition channel; registration depends entirely on direct word-of-mouth. |
| No activation/retention metrics | **Launch-blocking** for learning | Relay/AppView + Product | Soft launch with no instrumentation is a wasted experiment. Constitution-compatible design needed (below). |
| Verified-human supply chain not production-real (TW adapter, MobileMoica fail-closed) | **Important** (positioning risk, not a code gap) | Issuer / Product marketing | Partner-blocked. The wedge feature works mechanically (relay enforces `min_post_tier`) but the highest-assurance TW path is not live. Do not market MOICA-grade verification yet. |
| AppView ingest trusts relay signature check (no independent re-verify) | **Important** | AppView (Phase 2, pull slice forward) | G4. Undercuts the "independently verifiable" promise; the re-verify slice is cheap and on-brand. |
| External-host compliance level not persisted/consumed | **Important** | App + Relay (Phase 1.4) | G2. Discovery shows labels but ranking/sync/trust ignore them — a constitution Base-Rule-7/Scope obligation, but only bites once external hosts exist (post-soft-launch). |
| Abuse handling depth: tier-aware rate limits exist; peer-level token bucket + security metrics missing | **Important** | Relay (Phase 3, G8) | Reporting + moderation shipped (good). Bot-flood resistance at the connection level (Base Rule 4) is still partial. |
| Onboarding/empty-state guidance ("先建立身分" engineer-speak; no first-session guide) | **Important** | App / Product copy | Roadmap "Improve" items. First session must guide: join genesis boards → follow → first murmur. Pairs with cold-start. |
| Block/mute at the user level | **Nice-to-have** (verify) | App | Constitution Base Rule 6 expects "leave, mute, block, migrate." Moderation is host-scoped; confirm user-level block/mute exists before launch. |
| Relay ops table unbounded; no snapshots | **Nice-to-have for soft launch** | Relay (Phase 2) | G5. A scale problem, not a soft-launch problem. Defer. |
| Push platform credentials (APNS/FCM) | **Nice-to-have** | App/Ops config | Pipeline is content-free and shipped end-to-end; only credentials remain. In-app bell badge carries the loop without push at soft-launch scale. |

---

## Retention & growth loop analysis

**Working loops (shipped this week — this is real progress):**

- **Content → notification → return.** Replies/follows/messages/moderation outcomes
  fold into a local notification table during sync, with an in-app feed and an unread
  bell badge (README: Notifications Phase A+B). This is the core retention loop and it
  exists. The wake-push half is built and content-free (`{"hint":"sync"}`); even
  without APNS/FCM credentials the in-app badge carries the loop at soft-launch scale.
- **Moderation → notification.** A moderated author gets a local notification with the
  reason and keeps their content — constitution-aligned (Base Rule 6 reason-coded
  visibility) *and* a retention-preserving design choice. Good.

**Broken / missing loops:**

- **Share → visit → register (the acquisition loop) is closed.** No OG tags means a
  pasted Elix link renders as a naked URL in LINE/Threads/Messenger — no title, no
  preview, no pull. No share sheet means a user who wants to share a thread has no
  affordance. No universal/deep links means a tapped link can't open the app or land a
  web visitor on the right thread with a register CTA. **This is the single missing
  loop that most constrains growth**, and it is cheap to build.
- **Cold-start has no loop at all.** A new user lands in an empty network. There is no
  "here are 5 active boots to join" because there are no active boards. Discovery
  ranks by reputation tier over a set of zero. The first-session experience is the
  weakest part of the funnel and has no owner.
- **Verification → status → privilege loop is mechanically present but socially
  empty.** Trust-gated boards give a *reason* to upgrade to verified-human (you can
  post on 真人驗證版 boards). But with no seeded human-only boards worth posting in,
  the incentive to complete verification doesn't fire. Cold-start seeding directly
  unlocks the wedge's own upgrade loop.

**Net:** the *return* loop is shipped and good; the *acquire* and *first-session*
loops are absent. Growth is currently bottlenecked at the top of the funnel, not the
middle.

---

## Risk register

| Risk | Likelihood × Impact | Mitigation | Launch-blocking? |
|---|---|---|---|
| Empty network at launch (ghost town) | High × High | Genesis boards + seed content + default subscriptions + recruited founding posters before public link goes out | **Yes** |
| Key loss / unrecoverable accounts | High × High | Implement the Phase 1.0 recovery design (multi-device attestation + passphrase-encrypted backup; 72h veto on re-anchor) before public users exist | **Yes** |
| Over-promising TW gov-grade verification before adapter is live | Medium × High (trust/credibility) | Positioning discipline: market "human-verified, no real name"; treat MOICA as roadmap, not a launch claim; keep issuer fail-closed | No (positioning, not code) — but a credibility landmine |
| Sybil / bot flood overwhelming a small new community | Medium × High | Trust-gated boards (shipped) + tier-aware rate limits (shipped); complete peer-level token bucket (G8) before opening fully public boards | Important, not strictly blocking for an invite-gated soft launch |
| Moderation / legal exposure (Taiwan): defamation, illegal content, takedown obligations | Medium × High | Reporting + moderator console + host-scoped tombstones shipped; define a system-level break-glass path per the constitution's Exception Model (purpose/time/scope-limited, audited) for legal/safety; written takedown SOP for the host operator | Important — need a written legal-response SOP before launch even if tooling is adequate |
| Constitution compliance regressions (real-name creep, private-content leakage, raw-identity in logs) | Low × Very High | AGENTS.md constitution gate is active and enforced in specs; keep the compliance review current; the notification pipeline's content-free design shows the discipline is working | No (process is healthy) — but a single breach is brand-fatal, so keep the gate |
| Federation half-states (AT/PLC legacy, partial Nostr/AP) presenting broken or insecure behavior | Medium × Medium | Freeze AT/PLC (already decided); keep Nostr/AP as projection-only; AppView independent signature re-verification (G4) to honor the "verifiable" claim | No — but do not market federation until it is whole |
| Single-platform / split-team launch dilution | Medium × Medium | Pick iOS *or* Android for soft launch; finish one store | No |
| Observability blind spot (can't see signature reject rate, ingest lag, op growth, or activation) | High × Medium | Phase 0 observability baseline + the metrics proposal below | Important for operability and learning |

**Launch-blocking set:** ghost-town/cold-start, key-loss/recovery, and (for growth)
the absent sharing loop. The Taiwan legal SOP and a minimal metrics baseline are
"must-have-before-real-users" even though they are not code features.

---

## Privacy-preserving metrics proposal

Constraint: Base Rule 2 forbids sending private content / behavioral telemetry to
logs/analytics without explicit intent and a matching boundary; Base Rule 7 forbids
opaque global rules. So: **device-side aggregation, k-anonymous server-side counters,
no per-user behavioral event streams, no content in any metric, reason-coded
everything.** All of the below are aggregate counts or rates the relay/AppView already
need for operational exit criteria (Phase 0) — they piggyback on integrity
instrumentation, not on user surveillance.

| Metric | Definition | Why it is constitution-compatible |
|---|---|---|
| **New-anchor rate** | Count of new DID anchors registered at the relay per day (already a relay write). No identity attributes attached. | Anchors are already server-side records; counting registrations adds no new data path and no legal identity. |
| **Verified-human conversion** | (anchors that reach `verified_human` tier) ÷ (total active anchors), as a daily ratio, bucketed — never per-user. | Tier is already a public trust-tier input (Base Rule 4); the *aggregate* ratio reveals nothing about any individual and is the core wedge KPI. |
| **D1 / D7 return rate** | Of anchors created in week W, fraction that make ≥1 authenticated relay call on day 1 / day 7. Computed from existing relay request counters keyed by anchor, aggregated and k-anonymized (suppress buckets < k). | Uses the sync calls the relay already authenticates; no content, no behavioral trace beyond "active y/n." Suppression keeps it non-reidentifying. |
| **Board activity** | Per-board post + active-poster counts per day, public boards only, with a minimum-count floor before a board appears in the metric. | Public-board content is already public (Base Rule 2 distinguishes public from private); a count of public posts discloses nothing private. |
| **Notification → return correlation** | Aggregate: of devices that received a wake-push/badge on day D, fraction with an authenticated relay call within 24h. Device-side counted, only the aggregate ratio reported. | Push is already content-free (`{"hint":"sync"}`); measuring whether it drives return uses no content and can be device-aggregated before any report. |
| **Share-link → visit → register funnel** | Frontend: count of OG-link visits, of those that hit the register CTA, of those that complete an anchor. Aggregate counts only, no referrer PII, no cross-site identifiers. | Public web traffic counts; no user identity, no cross-site tracking — purely funnel volumes. (Becomes measurable once sharing ships.) |
| **Signature reject rate / ingest lag / op-table growth** | Relay+AppView operational series (Phase 0 exit criteria). | Pure system-integrity telemetry, no user data — already mandated by the architecture plan. |

Two North-Star candidates: **weekly active human-verified posters on gated boards**
(the wedge working) and **W1 return rate** (the loop working). Both are aggregate and
constitution-clean.

---

## Next 3 things to ship (before soft launch)

1. **Cold-start seeding — genesis boards + founding posters + first-session guide.**
   Pick 3–5 launch boards (at least 1–2 真人驗證版 human-only) tied to a real early
   community, recruit founding posters to fill them with genuine content *before* the
   public link, wire default subscriptions for new accounts, and replace the empty
   post-registration state with a guided path (join boards → follow → first murmur).
   *Why first:* every built surface (discover, feed, search, the verification upgrade
   incentive, the notification loop) is dead without content. Highest leverage,
   currently zero investment, no owner. It is mostly operations + a small client
   empty-state change, so it can run in parallel with engineering.

2. **Outbound sharing loop — OG meta tags on the frontend + native share sheet +
   universal/deep links.** Make a shared Elix thread render a rich preview in
   LINE/Threads/Messenger, give users a share affordance, and route taps to the app
   (or a web thread with a register CTA). *Why second:* it is the only organic
   acquisition channel and it is verified absent today; it is also cheap. Cold-start
   gives you content worth sharing; this turns that content into a growth loop.

3. **Identity recovery implementation (Phase 1.0 design) + a tested device-loss
   walkthrough.** Implement the anchor-as-portable-object, multi-device attestation,
   passphrase-encrypted backup, and the 72h re-anchor veto, then prove the
   lose-device-A-recover-on-device-B path end to end. *Why third (but in parallel):*
   it is the one true launch-blocking *foundation* gap — without it, every account you
   acquire is one device-loss away from gone, which is fatal for a self-sovereign
   product whose whole promise is "your identity and content are yours." The design is
   done; this is execution.

Honest trade-off: items 1–2 are growth, item 3 is foundation. A tiny team can't do all
three deeply at once. The sequencing call: **1 and 3 in parallel (different
people/skill sets — ops/content vs. Rust/relay), 2 immediately after 1** so there is
content to share. Bundle a minimal metrics baseline (new-anchor rate, W1 return,
board activity, share funnel) into items 1–2 so the soft launch actually teaches you
something.

---

## What's already strong (don't regress)

- **The constitution gate works.** Specs carry a Constitution Review; the
  notification pipeline is content-free by design; the compliance review tracks and
  *closes* gaps honestly (Email-OTP ≠ personhood, wallet rejects passport claims).
  This discipline is the brand. Keep it.
- **Trust-gated boards are a real, enforced differentiator** — `min_post_tier`
  enforced at both write chokepoints (signed ops + web sessions), surfaced as
  badge/gated composer/upgrade CTA in app and web. This is the wedge, and it shipped.
- **The verification supply chain is privacy-correct** — nullifier/`national_id_hash`
  stays inside the issuer boundary, never in the VC subject or verifier presentation
  (Base Rule 5). Do not let any "just log it for debugging" shortcut breach this.
- **The retention loop exists** — content → local notification → bell badge → return,
  with a content-free push pipeline ready. Most pre-launch products have nothing here.
- **Honest status reporting.** README and ROADMAP distinguish MVP vs. partial vs.
  legacy and call out compliance debt by name. Rare and valuable; keep it.
- **The hardware-custody deferral and AT/PLC freeze** show willingness to cut scope
  for launch value — exactly the instinct this review wants applied harder to
  federation breadth.
- **The recovery design is well-scoped** (all-Ed25519, custody-agnostic mount point,
  72h veto, no new server trust) — a good foundation to build item 3 on.
