# Scalable Following Feed — AppView Timeline Design

> Status: Draft for review
> Date: 2026-06-04
> Scope: Following feed (board posts + murmur/note) at network scale; AppView
> Component D; relay firehose; client feed-source abstraction; privacy model.
> Supersedes the "scale path" notes in the two MVP plans:
> `2026-06-04-following-feed-author-sync.md`, `2026-06-04-following-feed-murmur-note.md`.

## Problem

The MVP following feed (Design 1) has every client pull the **global** op delta
(`GET /api/v1/ops/delta`) and filter locally to the authors/boards it follows.

Cost structure:

- Per-client bandwidth/CPU = **O(total network op volume)**, independent of how
  few accounts the user follows.
- Relay egress = **O(users × total op volume)** — superlinear in network size.

This is acceptable at Genesis scale (~10³ users) and is privacy-friendly (the
relay learns no follow graph), but it breaks somewhere around **10⁴–10⁵ users**:
clients waste battery/data downloading ~99% irrelevant ops, and relay egress
explodes. We must design the scalable architecture now so MVP choices stay
forward-compatible, then build it in phases triggered by load.

## Goals / Non-Goals

**Goals**

- A following timeline whose per-client cost scales with **what you follow**, not
  with total network activity.
- Cover both content kinds on one path: board `post` and standalone
  `murmur`/`note` (the MVP plans route all of these through relay ops).
- Keep first-party constitution compliance: minimal disclosure, public-only
  distribution, reproducible projections, reason-coded, no opaque global ranking.
- Make the MVP forward-compatible so it is not throwaway.

**Non-Goals (this spec)**

- Full multi-region GKE cluster and Pub/Sub firehose (that is Phase C below;
  `genesis_hosting.md` Component C covers it).
- Ranking/recommendation algorithms beyond reverse-chronological + transparent,
  category-level filters.
- Cross-network (Nostr/ActivityPub) inbound aggregation of third-party authors.

## Architecture

Layered fan-out so the firehose is consumed by **infrastructure**, not by every
client.

```
 Author's app ──signed op──▶  Relay (Component C)            [exists]
                              ingest, verify Ed25519, append ops(log_id, author_did, ...)
                                      │  firehose
                                      ▼
                              AppView (Component D)           [NEW: ansible_appview/phoenix]
                              fold ops → Postgres projections indexed by author_did + log_id
                              (re-verify Ed25519 in batch; double verification)
                                      │  timeline API
                                      ▼
 Reader's app ──"timeline for {follow set}, since cursor"──▶ AppView
                returns only ops authored by those DIDs (fan-out-on-read)
```

- **Relay** stays the write/ingest + verification authority. Unchanged for
  Phase B; emits a firehose for Phase C.
- **AppView** is a new read-side service. It is an **acceleration artifact**:
  its Postgres is rebuildable from raw ops (constitution: reproducible public
  views; `genesis_hosting.md` D-5). Multiple AppViews can exist and must produce
  equivalent results from the same ops.
- **Client** swaps its feed source from "global-delta + local filter" to
  "AppView timeline query" behind an interface (see Forward-Compatibility).

### Firehose transport — phased

- **Phase B (AppView v1):** the AppView is the *single* consumer of the relay's
  **existing** `GET /api/v1/ops/delta` (it polls with a cursor). This replaces N
  client firehose pulls with **one**, and requires **no Pub/Sub** — the cheapest
  way to get the scaling win. Relay egress drops from O(users × ops) to
  O(AppViews × ops).
- **Phase C (scale):** relay forwards accepted ops to GCP Pub/Sub; AppViews
  subscribe; multi-region, batch Rustler verification, snapshots/replicas
  (`genesis_hosting.md` C-3/C-4, D-1/D-5).

## Read Model

**Fan-out-on-read with an author index.** AppView Postgres:

- `feed_items(log_id BIGINT PK, author_did TEXT, entity_type TEXT, entity_id TEXT,
  op_type TEXT, board_id TEXT NULL, thread_id TEXT NULL, visibility TEXT,
  created_at TIMESTAMPTZ, payload JSONB, sig_verified BOOL)`
  - Index: `(author_did, log_id DESC)` for timelines; `(board_id, log_id DESC)`
    for board feeds.
- Timeline query (reverse-chronological):
  `SELECT ... FROM feed_items WHERE author_did = ANY($follow_dids)
   AND log_id < $cursor AND visibility IN ('public','unlisted') AND NOT deleted
   ORDER BY log_id DESC LIMIT $n`
- Cursor = relay `log_id` (monotonic, already the global ordering key) — same
  cursor concept the MVP uses, so client paging logic carries over.

**Timeline API (sketch):**

```
POST /api/v1/timeline
  body: { dids: ["did:key:...", ...], cursor?: <log_id>, limit?: 50 }
  resp: { items: [...feed_items with public_key_hex...], next_cursor, has_more }

GET  /api/v1/board-feed?board_id=...&cursor=...   (board timelines)
```

The client still **verifies Ed25519 + DID-key binding** on returned items
(defense against a compromised AppView) — the AppView's `sig_verified` is an
optimization, not a trust root.

## Read Performance & Caching

A personalized timeline query (`author_did = ANY($follow_set)`) is **unique per
user**, so the *assembled result* is effectively uncacheable and, at high read
QPS, the database scatter-gather becomes the bottleneck. The fix is **not** to
cache the assembled result — it is to change what we read. Three levers, used
together:

**Lever 1 — Fan-out-on-write (push): make reads single-key and cacheable.**
Maintain a materialized per-reader timeline; when a public op is accepted, enqueue
its `item_id` into each follower's timeline.

```
home_timeline(reader_did, log_id, item_id)        -- or a Redis list per reader
read = WHERE reader_did = $me ORDER BY log_id DESC LIMIT n   -- single partition, index-only
```

The read is keyed by **one** `reader_did`, so it is index-only and per-user
cacheable. Cost moves to write: write amplification O(#followers), storage
O(Σ followers), and the **celebrity** problem (a very-high-follower author causes
a huge write fan-out per post).

**Lever 2 — Building-block caching: cache the shared pieces, merge at read.**
Even when the assembled result is not cacheable, its inputs are shared and highly
cacheable:

- per-author recent-item id list (cache key = `author_did`) — a popular author is
  cached once and served to *all* followers (high hit rate);
- item objects (cache key = `item_id`).

Read = fetch N cached per-author lists + k-way merge + hydrate cached items →
mostly cache, little/no DB, and **no write amplification**. This makes
fan-out-on-read scale by removing the DB from the hot path.

**Lever 3 — Delta reads over the local-first client cache.** The client persists
its timeline (Drift), so steady-state reads are "new items since my cursor" — a
small tail, not a full rebuild. The expensive full build happens only on cold
start / backfill. With Lever 1 this delta is a single-key tail read.

**Scaling stages of the read model:**

1. **Fan-out-on-read + building-block cache (Lever 2 + Lever 3).** Phase B
   default: per-author lists and item objects in Redis, read-time merge, client
   delta reads. Removes the DB-per-query bottleneck **without** write
   amplification. Good to large follow sets / moderate author volume.
2. **Hybrid fan-out-on-write (Lever 1) for the bulk + fan-out-on-read for
   celebrities, merged at read.** Phase C: normal authors pushed into per-reader
   timelines (cheap, cacheable single-key reads); cap fan-out and handle
   very-high-follower authors on the read path from cached per-author lists. This
   is the standard production model (Twitter/Instagram).

**Supporting techniques:** first-page short-TTL per-user cache (absorbs refresh
storms), seek/cursor pagination on `log_id` (no OFFSET scans), shard
`home_timeline` by `reader_did`, read replicas, and append-only immutability that
makes per-author/item caches safe to keep.

**Trade-offs:** Lever 1 makes the AppView store each reader's materialized
timeline and hold the follow graph server-side — deepening the privacy trade-off
(still federated-follows-only; localOnly follows stay client-side and merge
locally) and growing storage with Σ follower counts (bounded by retention windows
+ fan-out caps). The materialized timeline remains a **reproducible projection**
of ops + follow graph, not a source of truth.

## Privacy Model (the core trade-off)

Computing a personal timeline server-side requires the server to know who you
follow. This conflicts with minimal disclosure. We resolve it with the **follow
visibility** the data model already carries (`FollowVisibility.localOnly` vs
`federated`):

- **Federated follows → AppView-served.** The user explicitly chose federation
  for these relationships, so disclosing them to a first-party, constitution-
  bound AppView is consistent with their choice. The AppView MUST NOT log or
  persist the per-request follow set beyond what indexing requires, and MUST NOT
  expose one user's follow set to others.
- **localOnly (private) follows → never sent to the AppView.** They are resolved
  client-side (the Design-1 local filter remains as a residual path over a
  smaller candidate set), trading scale for privacy on those specific follows.
- A user who wants a fully private feed can keep all follows localOnly and accept
  reduced scale/coverage.

This makes the privacy posture an explicit, per-relationship user choice rather
than a silent global downgrade — consistent with Base Rule 2/3 and the
compliance-level model for hosts.

## Constitution Review

1. **Identity:** follower DID + author DIDs only; no Wallet/TW-identity payloads
   in ops or timeline.
2. **Data leaving device:** only **public/unlisted** content is indexed/served
   (private/localOnly fail closed at the author's publish boundary — already
   enforced). Federated follow sets are disclosed to the AppView only by explicit
   user choice; localOnly follows never leave the device.
3. **Minimum claim:** distribution only; no verification claim.
4. **Raw legal identity excluded** from ops, projections, logs, timeline.
5. **Ranking/moderation:** default reverse-chronological; any filter must be
   transparent at least at category level; no opaque global ranking (Base Rule
   7). Reason codes (`followedUser`/`followedBoard`) preserved in client render.
6. **Personhood/duplicate key:** none.
7. **Exit/revoke:** unfollow stops inclusion (federated: drop from query set;
   localOnly: existing purge). AppView holds only public ops, which are already
   distributed; user content control is unchanged.
8. **External host compliance:** AppView is first-party (MUST comply). Additional
   AppViews/relays carry a compliance level before influencing trust/ranking.

**Reproducibility requirement:** AppView Postgres MUST be a pure projection of
relay ops — rebuildable, no source-of-truth state. Moderation = signed
tombstone ops / render policy, never silent deletion (Base Rule 7;
`genesis_hosting.md` §5).

**Verdict:** Compliant, conditional on (a) public-only indexing, (b) federated-
only follow-set disclosure with no follow-set logging, (c) client-side
re-verification, (d) reproducible projections.

## Forward-Compatibility: what the MVP MUST do now

So the MVP is not throwaway, the two MVP plans must adopt these now:

1. **Client feed-source abstraction.** Introduce a `FollowFeedSource` interface
   with the MVP implementation `LocalDeltaFilterSource` (Design 1). The AppView
   client becomes `AppViewTimelineSource` later — a config swap, not a rewrite.
   The `FollowFeedProjector` / `ContentItemFeedProjector` sit behind this.
2. **All feedable content flows through relay ops** with `author_did` + `log_id`.
   Board posts already do; the murmur/note plan adds murmur/note ops. This is the
   single indexable substrate the AppView needs — do not add a content kind that
   bypasses ops.
3. **`log_id` is the universal cursor** across global delta, AppView timeline, and
   board feeds. Client paging keyed on `log_id` only.
4. **Record follow visibility** (`localOnly` vs `federated`) on every follow —
   already in the model; ensure the UI sets it intentionally.
5. **Payloads carry `visibility`** for post/murmur/note so the AppView can filter
   public/unlisted without decoding app-private fields; `privateTagsJson` and
   other local-only fields never enter op payloads.

These are small additions to the MVP plans and cost little now; skipping them is
what would force a rewrite later.

## Phasing and Triggers

- **Phase A — MVP (now):** Design 1 + items 1–5 above. Ships on Genesis.
- **Phase B — AppView v1 (trigger-driven):** build `ansible_appview/phoenix`:
  poll relay global delta → Postgres author/board index (Rustler verify) →
  `POST /api/v1/timeline` + board-feed API, with **fan-out-on-read + Redis
  building-block cache (per-author lists + item objects) + client delta reads**
  (read-model stage 1). Client `AppViewTimelineSource` for federated follows;
  localOnly stays local. **No Pub/Sub, no write fan-out.**
  - *Triggers (any):* per-client daily delta > ~5–10 MB; active users > a few ×10³;
    relay firehose egress beyond budget. Pick concrete numbers from staging
    telemetry before building.
- **Phase C — Scale (trigger-driven):** hybrid **fan-out-on-write** materialized
  per-reader timelines + celebrity handling (read-model stage 2), Pub/Sub
  firehose, multi-region AppViews, batch verification, `home_timeline` sharding,
  signed MST snapshots + read replicas, Cloud CDN/Armor (`genesis_hosting.md`
  C/D). Triggered when read QPS / cache-miss cost on stage 1 exceeds budget.

## Open Questions

- Exact celebrity threshold and whether hybrid fan-out-on-write is ever needed at
  Tris-Aura's projected scale (measure first).
- Whether federated follow records should themselves be signed/public (enabling
  AppView server-side join without per-request follow lists) vs client-supplied
  follow sets — affects the privacy model nuance and AppView statefulness.
- Multi-AppView equivalence testing: how to assert two AppViews produce the same
  timeline from the same ops (snapshot/replay conformance).

## Next Artifacts

- Implementation plan: `ansible_appview/phoenix` Component D (Phase B) +
  client `FollowFeedSource` abstraction (the MVP forward-compat slice).
- Update the two MVP plans to add the five forward-compatibility items and
  reference this spec.
