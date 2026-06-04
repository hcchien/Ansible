# AppView Component D — Phase B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first scalable read side of the following feed: a new
`ansible_appview/phoenix` service (Component D) that consumes the relay op stream,
folds it into a Postgres index keyed by `author_did` + `log_id`, and serves a
per-follower timeline so clients no longer download the global firehose.

**Design source (read first):** `docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md`.
This plan implements **Phase B** of that spec: fan-out-on-read + building-block
cache + client delta reads. **No Pub/Sub, no fan-out-on-write** (those are Phase
C). MVP following feed (Design 1) remains the fallback and the source for
`localOnly` follows.

**Depends on:** the `FollowFeedSource` abstraction (board-post plan Task 7) and
all feedable content flowing through relay ops (board-post + murmur/note plans).

## Source Context

- Relay op stream (the input): `ansible_relay/phoenix/lib/ansible_relay/web/controllers/ops_controller.ex`
  — `GET /api/v1/ops/delta?cursor=&limit=` returns `{ops:[{op_id, author_did, entity_type, entity_id, op_type, payload, signature, public_key_hex}], next_cursor, has_more}`.
- Op model: `ansible_relay/phoenix/lib/ansible_relay/db/op.ex` (monotonic `id` = `log_id`).
- Reuse the relay's Ed25519 verification NIF pattern: `ansible_relay/phoenix/native/sig_verifier_nif/` + `lib/ansible_relay/sig_verifier.ex`.
- Relay Dockerfile/cloudbuild as the template: `ansible_relay/phoenix/Dockerfile`, `cloudbuild.yaml`.
- Client feed source: `ansible_core/domain/lib/src/follow/follow_feed_source.dart` (from board-post Task 7).

## Constitution Review

Touches federation, sync, ranking/distribution; first-party service → MUST comply.

1. **Identity:** indexes `author_did` and serves to a requester identified by its
   federated follow set. No Wallet/TW-identity data.
2. **Data leaving device / disclosure:** AppView indexes only **public/unlisted**
   ops (filter on `visibility`; drop anything else — defense in depth over the
   relay/app gates). The timeline request carries the requester's **federated**
   follow DIDs only; `localOnly` follows are never sent (resolved client-side).
   The follow set MUST NOT be logged or persisted beyond the request.
3. **Minimum claim:** none; distribution only.
4. **Raw legal identity excluded** from projections, indexes, logs, responses.
5. **Ranking/moderation:** timeline is reverse-chronological by `log_id`; no
   opaque global ranking. Tombstone/delete ops are honored as deletions, never
   silent mutation. Reason codes are a client render concern.
6. **Personhood/duplicate key:** none.
7. **Exit/revoke:** unfollow drops a DID from the client's query set immediately;
   AppView holds only already-public ops.
8. **Reproducibility (MUST):** the Postgres index is a pure projection of relay
   ops — rebuildable from `cursor=0` (Task 7). It is an acceleration artifact,
   not a source of truth. Two AppViews fed the same ops MUST produce equivalent
   timelines.
9. **Verification (MUST):** AppView re-verifies Ed25519 + DID-key binding before
   indexing; clients re-verify returned items (AppView `sig_verified` is an
   optimization, not a trust root).

**Verdict:** Compliant, conditional on public-only indexing, no follow-set
logging, reproducible projection, and double verification.

## Architecture (Phase B)

```
Relay  GET /api/v1/ops/delta (cursor)  ──poll──▶  AppView ingest worker
                                                   verify Ed25519 (NIF), fold → Postgres
                                                   ETS building-block cache (per-author lists, items)
Client  POST /api/v1/timeline {dids, cursor}  ──▶  AppView  → merge cached per-author lists → page
```

- Single consumer of the firehose (replaces N client pulls). No Pub/Sub.
- Cache = in-process **ETS** for v1 (single instance). Redis only when the AppView
  scales to multiple instances (note in Task 5; not built now).

**Tech stack:** Elixir/Phoenix (Bandit+Plug, mirroring the relay), Ecto + Postgres,
Rustler NIF for Ed25519, `mix test`. Client side: Dart (`dart test`).

---

## Task 1: AppView service skeleton

**Files:** new `ansible_appview/phoenix/` (mix project), mirroring `ansible_relay/phoenix` layout.

- [ ] **Step 1:** Scaffold a mix project `ansible_appview` with deps `plug`, `bandit`, `jason`, `ecto_sql`, `postgrex`, `rustler` (copy versions from the relay `mix.exs`). Add `AnsibleAppview.Application` starting `Repo` + `{Bandit, plug: AnsibleAppview.Web.Router, port: PORT}`.
- [ ] **Step 2:** Add `config/{config,dev,test,runtime}.exs` mirroring the relay. `runtime.exs` requires `DATABASE_URL`, `RELAY_BASE_URL`, `PORT` (default 8080).
- [ ] **Step 3:** Add `AnsibleAppview.Release.migrate/0` (copy the relay's release module — release image has no `mix`).
- [ ] **Step 4:** Health route `GET /health` → 200. `mix compile` + a smoke test green. **Commit** `feat(appview): service skeleton`.

## Task 2: Postgres projection schema

**Files:** `ansible_appview/phoenix/priv/repo/migrations/*`, `lib/ansible_appview/db/feed_item.ex`, `ingest_cursor.ex`.

- [ ] **Step 1: Failing test** asserting the migration creates `feed_items` and `ingest_cursors`.
- [ ] **Step 2:** `feed_items(log_id BIGINT PK, op_id TEXT UNIQUE, author_did TEXT, entity_type TEXT, entity_id TEXT, op_type TEXT, board_id TEXT NULL, thread_id TEXT NULL, visibility TEXT, created_at TIMESTAMPTZ, payload JSONB, public_key_hex TEXT, deleted BOOL DEFAULT false, sig_verified BOOL)`. Indexes: `(author_did, log_id DESC)`, `(board_id, log_id DESC)`.
- [ ] **Step 3:** `ingest_cursors(source TEXT PK, cursor BIGINT)` (persisted relay delta cursor).
- [ ] **Step 4:** `mix test` green. **Commit** `feat(appview): feed_items projection schema`.

## Task 3: Ed25519 verification NIF

- [ ] Copy/port the relay `sig_verifier_nif` + `AnsibleAppview.SigVerifier.verify_ed25519/3` and the canonical signing-payload helper so verification is byte-identical to the relay/app. Test with a known vector. **Commit** `feat(appview): ed25519 verifier`.

## Task 4: Ingest worker (relay delta → projection)

**Files:** `lib/ansible_appview/ingest/relay_poller.ex`, `lib/ansible_appview/ingest/folder.ex`, tests.

- [ ] **Step 1: Failing test.** Given a fake relay delta payload with valid + invalid-signature ops and mixed visibility, the folder inserts only **valid + public/unlisted** ops into `feed_items`, maps `entity_type` (post/thread/board/murmur/note) and extracts `board_id`/`thread_id`/`visibility`/`created_at` from the payload, advances the cursor, and is idempotent on `op_id` (no dupes).
- [ ] **Step 2:** `Folder.apply(ops)` — re-verify each op (Task 3); reject non-`public`/`unlisted`; decode `payload` JSON to extract indexed columns; upsert by `op_id`; honor `op_type == delete` (set `deleted = true`).
- [ ] **Step 3:** `RelayPoller` GenServer — loop: read cursor → `GET {RELAY_BASE_URL}/api/v1/ops/delta?cursor=&limit=500` → `Folder.apply` → persist `next_cursor`; backoff on error; never log payload contents or follow data.
- [ ] **Step 4:** Wire into the supervision tree. `mix test` green. **Commit** `feat(appview): relay ingest worker`.

## Task 5: Timeline + board-feed API with building-block cache

**Files:** `lib/ansible_appview/web/router.ex`, `controllers/timeline_controller.ex`, `cache/author_cache.ex` (ETS), tests.

- [ ] **Step 1: Failing test.** `POST /api/v1/timeline` with `{dids:[a,b], cursor, limit}` returns only `feed_items` whose `author_did ∈ {a,b}`, `visibility IN (public,unlisted)`, `NOT deleted`, ordered `log_id DESC`, paginated by `log_id` with `next_cursor`/`has_more`, each item including `public_key_hex` for client verification. A follow set member with no posts contributes nothing; an empty `dids` returns empty.
- [ ] **Step 2:** Implement the query (`author_did = ANY($dids) AND log_id < $cursor ...`). Add `GET /api/v1/board-feed?board_id=&cursor=`.
- [ ] **Step 3: Building-block cache (ETS).** `AuthorCache` holds each author's recent `[{log_id, item}]` and item objects; timeline read merges cached per-author lists and only falls to Postgres on cache miss / older pages. Cache is invalidated/extended by the ingest folder as new ops land. Document that multi-instance deployment requires Redis instead of ETS (not built in Phase B).
- [ ] **Step 4: Privacy.** Assert in tests that the request handler never logs `dids`. `mix test` green. **Commit** `feat(appview): timeline + board-feed API with author cache`.

## Task 6: Client `AppViewTimelineSource`

**Files:** `ansible_core/domain/lib/src/follow/appview_timeline_source.dart` (impl of `FollowFeedSource`), a thin `AppViewClient` in the app, tests.

- [ ] **Step 1: Failing test.** `AppViewTimelineSource.fetch(followerDid, cursor, limit)` resolves the follower's **federated** follow DIDs, calls a `timeline` transport (mocked) with those DIDs, **verifies Ed25519 + DID-key binding on each returned item** (reuse existing verifier), and returns a `FollowFeedPage`. `localOnly` follows are excluded from the request and merged from the local projector instead.
- [ ] **Step 2:** Implement; keep the relay-`log_id` cursor semantics identical to `LocalDeltaFilterSource`. Selecting source (local vs appview) is config/DI.
- [ ] **Step 3:** `dart test` + `dart analyze` green. **Commit** `feat: AppView timeline client source`.

## Task 7: Rebuild + reproducibility

- [ ] Add `AnsibleAppview.Release.rebuild/0` (or a mix task) that truncates projections and re-folds from `cursor=0` via the relay delta. Test that a rebuild reproduces the same `feed_items` as incremental ingest for a fixed op set (reproducibility MUST). **Commit** `feat(appview): projection rebuild`.

## Task 8: Deployment

**Files:** `ansible_appview/phoenix/Dockerfile`, `cloudbuild.yaml`; update `docs/deployment/cloud_run_deploy.md`.

- [ ] **Step 1:** Dockerfile + cloudbuild mirroring the relay (image `ansible-appview`, region/repo identical).
- [ ] **Step 2:** Add a `cloud_run_deploy.md` section: deploy `ansible-appview` (own Cloud SQL DB or schema; `RELAY_BASE_URL` to the relay; migration job; **single instance for Phase B** because the cache is in-process ETS — note Redis + multi-instance as the Phase C upgrade).
- [ ] **Step 3:** `mix test` full suite green. **Commit** `feat(appview): deployment config`.

---

## Definition of Done (Phase B)

- A client with federated follows gets its timeline from the AppView; per-client
  cost scales with the follow set, not total network volume.
- AppView indexes only public/unlisted ops, re-verifies signatures, never logs
  follow sets, and its Postgres is rebuildable from `cursor=0`.
- `localOnly` follows still resolve via the local Design-1 path.
- Client re-verifies every item returned by the AppView.
- `mix test` (appview + relay) and `dart test` (domain) green.
- Phase C items (Pub/Sub firehose, fan-out-on-write, Redis, multi-instance,
  multi-region, celebrity handling) are explicitly **out of scope** and tracked in
  the scale spec.
