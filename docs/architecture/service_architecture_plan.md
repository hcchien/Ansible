# Service Architecture Plan v1.0

> Status: Active plan
> Date: 2026-06-12
> Scope: relay, appview, issuer, distribution frontend, app sync/identity
> boundary — how the current MVP services evolve into the launch and
> at-scale architecture.
>
> This is the architecture-level companion to [docs/ROADMAP.md](../ROADMAP.md)
> (feature planning). It consolidates the gaps scattered across the
> [compliance review](../superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md),
> [SOSP](../security/sosp.md) component TODOs,
> [scaling operations](../deployment/scaling_operations.md) follow-ups,
> [genesis hosting](genesis_hosting.md) targets, and the
> [federation strategy](../protocol/tris_aura_federation_strategy_v0.1.md)
> into one sequenced plan.

## Constitution Review

Per [AGENTS.md](../../AGENTS.md), this plan touches identity, storage, sync,
federation, and ranking. Checklist answers:

1. **Identity/credentials involved:** app-held DID signing keys, Nostr keys,
   VC trust anchors. Phase 1 gives them a recovery path and explicit
   custody-class labeling (Base Rule 1's reduced-trust branch); hardware
   custody is deferred to an opt-in upgrade — identity autonomy is
   strengthened either way, never weakened.
2. **Data leaving the device:** no new paths. Phases 2–3 change *how* already
   chosen distribution paths are stored/delivered (partitioning, push), never
   *what* is distributed. Private content remains fail-closed (Base Rule 2).
3. **Minimum claim:** unchanged; Phase 2 ingest verification re-checks
   signatures, it does not add identity claims.
4. **Raw legal identity:** unaffected; no phase introduces raw identity into
   relay payloads, logs, or federation payloads.
5. **Trust/ranking changes:** Phase 1 makes external-host compliance level a
   policy input — reason-coded per Base Rules 4/7.
6. **Personhood bindings:** unchanged (issuer boundary stays as reviewed).
7. **Exit/rotation:** Phase 1.0 makes this explicit — recovery, re-anchor, and
   anchor portability are designed *before* hardware custody lands, so the
   custody upgrade never removes the user's exit or recovery path; reduced-
   trust mode preserves a lower-trust option throughout.
8. **External hosts:** compliance level becomes persisted and policy-readable
   (closing the review's second remaining gap).

## 1. Current State（現況）

```
┌─ Device boundary ─────────────────────────────┐
│ Flutter app (ansible_node/app)                │
│  ├─ Drift SQLite (canonical local content)    │
│  ├─ Rust FFI (Ed25519, MST, Lexicon signing)  │
│  └─ keys: raw hex in flutter_secure_storage ⚠ │
└──────┬──────────────┬─────────────────────────┘
       │ XRPC/REST    │ Nostr (client→relay, direct)
       ▼              ▼
┌─ Relay / Forum Host (Phoenix, :4001) ─────────┐     ┌─ Nostr relays ─┐
│  DID anchor · op store (append-only, ⚠ growth)│     └────────────────┘
│  forum host · web sessions · ActivityPub MVP  │
│  discovery · reputation mapping               │
└──────┬──────────────────────┬─────────────────┘
       │ op-delta HTTP poll ⚠ │ AP federation (retry in Postgres ⚠)
       ▼                      ▼
┌─ AppView (Phoenix, :4003) ──┐    ┌─ Fediverse ─┐
│  PG projection · timelines  │    └─────────────┘
│  follow graph · discovery   │
│  ingest trusts relay sig ⚠  │
└─────────────────────────────┘
┌─ Issuer (Go, :4002) ────────┐  ┌─ Frontend (Node, :5173) ──┐
│  W3C VC · did:web · TW/     │  │  Forum Host public views  │
│  MobileMoica (fail-closed)  │  │  app-approved web sessions│
└─────────────────────────────┘  └───────────────────────────┘
```

⚠ = known architectural debt addressed by this plan.

Identity is protocol-neutral per the federation strategy: AT Protocol/`did:plc`
is a compatibility context; Nostr and ActivityPub are first-class projection
adapters; the app signs intents, the relay distributes.

## 2. Gap Inventory（缺口清單）

| # | Gap | Source | Severity |
|---|---|---|---|
| G1 | Raw private key hex in secure storage; no hardware custody, no reduced-trust mode | Compliance review | **Launch blocker** — closes via explicit custody-class labeling (Phase 1); hardware custody itself deferred to Later (opt-in upgrade, product decision 2026-06-13) |
| G2 | External-host compliance level not persisted locally, not consumed by ranking/sync/trust | Compliance review | **Launch blocker** |
| G3 | No `zeroize`/`secrecy` in `ansible_rust_core` (key material lingers in memory) | SOSP A-1 | High |
| G4 | AppView ingest trusts relay's signature check; no independent re-verification, signed payloads not retained | SOSP D-1, scaling §5 | High |
| G5 | Relay `ops` table unbounded; no partitioning, snapshots, or retention | Scaling §1 | High |
| G6 | Client + AppView pull by polling (thundering herd at scale) | Scaling §2, genesis C-3 | Medium |
| G7 | ActivityPub/messenger delivery fan-out backed by Postgres retry loop (no backpressure, no dead-letter) | Scaling §3 | Medium |
| G8 | Peer-level token bucket + security metrics missing in abuse detection | SOSP C-1 | Medium |
| G9 | Nostr production key custody incomplete | README, federation strategy | Medium |
| G10 | ActivityPub federation behaviors incomplete (full inbox handling, Undo/Reject paths) | README | Medium |
| G11 | DNS handle verification not started | README | Low |
| G12 | Standalone reputation labeler (tier mapping lives inside relay) | README | Low |
| G13 | Multi-region / multi-AppView (genesis target) | genesis_hosting.md | Later |
| G14 | No identity recovery path — single-device raw keys already make device loss = permanent identity loss; constitution requires migration/recovery without operator authority | Base Rule 1; this review | **Launch blocker** — design written 2026-06-13 |
| G15 | Relay is the de facto identity authority: anchors are relay DB rows, not user-signed portable objects; identity/forum/federation data not schema-separated | Base Rule 1; this review | High |
| G16 | No app↔relay API versioning/negotiation — op format evolution (Phase 2) will break long-tail clients | This review | High |
| G17 | No observability baseline — phase exit criteria (signature rejection rate, op growth, ingest lag) have no metrics to stand on | SOSP C-1 (partial); this review | High |

## 3. Target Architecture（目標架構）

At **launch**: same five services, with (a) hardware-held or explicitly
reduced-trust keys on device **plus a working recovery path**, (b) every
public fold independently signature-verified, (c) bounded relay storage with
signed snapshots, (d) compliance level as a first-class policy input across
ranking/sync/trust, (e) DID anchors as user-signed, self-certifying objects
that can be re-presented to a different relay — the relay stores and serves
anchors but is not the sole authority over identity continuity.

At **scale**: push-based op distribution (WebSocket firehose with jittered
backoff), queue-backed delivery workers, partitioned op storage with archived
snapshots, CDN-fronted frontend, and the genesis multi-region topology — all
without changing the trust model established at launch.

Deliberate non-goals (unchanged from the federation strategy): the app never
implements ActivityPub server endpoints; Nostr/AP stay projections, never the
canonical store; GCP Pub/Sub is **not** required for single-region scale —
Phoenix PubSub + WebSocket replaces the genesis C-3 Pub/Sub assumption until
multi-region demands otherwise (decision D2 below).

## 4. Phased Plan（分階段計畫）

### Phase 0 — Cross-cutting foundations (start immediately, runs alongside)

Closes G16, G17. Cheap now, expensive to retrofit.

1. **API versioning — ✅ done 2026-06-13** (closes G16): the app sends
   `x-ansible-protocol: 1` on every relay/appview call; both servers
   advertise `{current, min_supported}` at `GET /api/v1/meta` and enforce
   the minimum via a router plug (missing/newer headers pass; older →
   `426 upgrade_required`, mapped to a friendly "update the app" message).
   Ops carry an independent `schema_version` (column on the relay `ops`
   table, validated `1..current`, kept out of the signed payload so
   signatures stay valid); the app op builder stamps it and sync skips
   unknown-future-version ops instead of misparsing them.
2. **Observability baseline**: metrics endpoints (PromEx or equivalent) on
   relay/appview, request + ingest counters on issuer/frontend; the specific
   series each later phase needs as exit criteria — op-table growth rate,
   delta-poll QPS, signature verification pass/reject, AppView ingest lag,
   delivery queue depth — defined here so the phases can be measured.

### Phase 1 — Identity recovery & trust policy (launch blockers)

Closes G14, G2, G3; G1 closes via Base Rule 1's explicit reduced-trust
branch (custody-class labeling), **hardware custody itself deferred to
Later by product decision (2026-06-13)** — too high a user barrier now;
the recovery design keeps a custody-agnostic mount point for it.

0. **Identity recovery & re-anchor design — ✅ written 2026-06-13**
   ([design](../superpowers/plans/2026-06-13-identity-recovery-reanchor-design.md),
   v1.1 hardware-deferred): key hierarchy (backupable Ed25519 identity key
   + never-backed-up software device keys), multi-device attestation,
   NIP-49-style passphrase backup, self-certifying hash-chained anchor
   (G15's portability half), re-anchor flows with a 72h recovery veto
   window. Decisions D1 (deferred w/ preserved analysis) and D5 settled.
1. **Recovery implementation** (per the design's task outline): anchor
   object in rust core, backup create/restore + device enrollment + 
   recovery wizard in app, chain-verifying anchor store + re-anchor
   endpoints + veto/alerts on relay. `did_accounts` becomes a cache.
2. **Custody-class labeling (reduced-trust made explicit)**: anchors and
   device records carry `custody_class: software`; registration UX states
   plainly that keys are software-held; fix code comments that overclaim
   enclave custody. This is the constitution-compliant posture until
   hardware ships as an opt-in upgrade.
3. **Memory hygiene**: add `zeroize`/`secrecy` to `ansible_rust_core` secret
   buffers; tests for zeroing.
4. **Compliance-level policy use**: persist `constitution_compliance` on local
   `ForumHost`/`RemoteNode` rows (default `unknown`); discovery ranking,
   board sync gating, and recommendation read it; reason-coded UI label.

Exit criteria: compliance review G14 flips to compliant and G1 to
"compliant via explicit reduced-trust mode"; **a documented, tested
device-loss recovery walkthrough** (lose device A, recover identity on
device B via backup or second device, relay accepts the re-anchor;
remaining enrolled devices receive the identity alert and can veto).

### Phase 2 — Data-plane integrity & durability

Closes G4, G5, G15 (schema half). Relay + AppView.

1. **AppView independent verification** (SOSP D-1): Rustler batch Ed25519
   verifier at ingest; require valid signature **and** non-expired DID anchor
   before folding into public projections; persist verification status +
   source provenance on `feed_items`.
2. **Retain signed payloads**: store original signed record + signature
   alongside projections so clients/third parties can re-verify (scaling §5).
3. **Relay op storage lifecycle**: time-based partitioning of `ops`; signed
   snapshot format so AppView rebuilds don't require full history; retention
   policy for archived partitions (tombstones remain authoritative locally).
4. **Relay internal schema separation**: identity-anchor, forum-host, and
   federation data live in separable schema/table groups with no cross-group
   joins in hot paths. The relay stays one deployable (splitting now would be
   premature), but each concern keeps its own data ownership so a future
   extraction is a deployment change, not a rewrite.

Exit criteria: AppView rebuild-from-snapshot tested; ops partitions rotating
in staging; public fold rejects bad signatures with reason-coded metrics.

### Phase 3 — Push distribution & delivery workers

Closes G6, G7, G8. Relay + AppView + app sync layer.

1. **Op firehose over WebSocket** (Phoenix Channels): AppView subscribes
   instead of polling (`INGEST_INTERVAL_MS` becomes the fallback); app delta
   sync gains ETag/304 + jittered backoff immediately (cheap, ship first).
2. **Delivery workers**: move ActivityPub + messenger outbound fan-out to Oban
   queues with backpressure, retries, and dead-letter visibility; redacted
   reason-coded failure events.
3. **Abuse detection completion**: peer-level invalid-message token bucket +
   security metrics (SOSP C-1 remaining boxes); Redis-backed when `REDIS_URL`
   is set (already the pattern for the rate limiter).

Exit criteria: AppView ingest lag measured via push in staging; zero polling
from AppView under normal operation; delivery queue depth + dead-letter
dashboards exist.

### Phase 4 — Federation completion

Closes G9, G10, G11, G12. Independent of Phases 2–3; can interleave.

1. **Nostr key custody**: Nostr signing keys join the Phase 1 custody model
   (hardware-held or reduced-trust); NIP-49 encrypted export for portability.
2. **ActivityPub federation behaviors**: full inbox activity handling
   (`Follow`/`Accept`/`Reject`/`Undo`), remote reply/mention mapping back into
   domain events, per-instance error tracking.
3. **DNS handle verification**: DNS TXT + HTTPS `/.well-known` lookup as a
   trust-tier input (README 🔜 item).
4. **Reputation labeler extraction**: split VP→tier mapping into a service
   with its own audit log once more than one consumer needs it — extraction is
   conditional, not automatic (decision D3).

### Phase 5 — Scale-out（genesis target）

Closes G13. Only after Phases 2–3 are stable in production.

- Multi-region relay presence per genesis_hosting.md (regional Phoenix +
  global ingress, DID cache handoff).
- Cross-region op distribution — *this* is where GCP Pub/Sub (or NATS)
  replaces Phoenix PubSub if needed (decision D2).
- Multi-AppView reproducible projections (AppView design doc).
- Frontend CDN + WAF (Cloud Armor) per scaling §4.

## 5. Decision Points（待決事項）

| # | Decision | Default position |
|---|---|---|
| D1 | Hardware custody approach (Secure Enclave P-256 vs ES256 migration) | **Deferred (product decision 2026-06-13: user barrier too high)** — device keys are software Ed25519 with `custody_class` labeling; when hardware returns it's an opt-in per-device upgrade via dual-key attestation, zero protocol change; ES256 identity-key migration permanently rejected (makes recovery unsolvable). See the [Phase 1.0 design](../superpowers/plans/2026-06-13-identity-recovery-reanchor-design.md) §D1 |
| D2 | Cross-service op transport at scale: Phoenix PubSub vs GCP Pub/Sub vs NATS | Phoenix Channels single-region (Phase 3); revisit only at Phase 5 multi-region |
| D3 | Standalone labeler timing | Extract only when a second consumer (external AppView or moderation tooling) exists |
| D4 | Oban vs hand-rolled queue for delivery workers | Oban (battle-tested, Postgres-native, no new infra) |
| D5 | Recovery mechanism mix: multi-device attestation, passphrase-encrypted content-key backup, recovery credential — which are launch-required vs later | **Settled (pending owner review):** multi-device attestation + encrypted backup at launch (no new server trust); issuer-assisted recovery credential later behind its own constitution review; social recovery out of scope — see the [Phase 1.0 design](../superpowers/plans/2026-06-13-identity-recovery-reanchor-design.md) |
| D6 | Issuer trust anchor: relay pins a single `ISSUER_DID`/pubkey via env — needs a rotation/multi-key story before first issuer key rotation | Move to a small signed issuer-key document (did:web already serves one) consumed by relay; low urgency, schedule with Phase 4 |

## 6. Sequencing & Ownership（順序與依賴）

```
Phase 0 (cross-cutting)  ── starts now, runs alongside everything
Phase 1 (app/rust/core)  ── 1.0 recovery design gates 1.1–1.2 ──►  launch gate
Phase 2 (relay/appview)  ──────────►  needed before meaningful external traffic
Phase 3 (relay/appview)  ── after 2 (snapshots make push restart-safe)
Phase 4 (federation)     ── 4.1 after Phase 1; 4.2–4.4 independent
Phase 5 (infra)          ── after 2+3 stable in prod
```

Phases 1 and 2 can run in parallel (different services), but Phase 1.0's
anchor-as-portable-object design should be agreed before Phase 2 freezes the
ops/snapshot schema, so anchors and ops don't diverge. Within each phase,
items are ordered by dependency. Each item should get its own plan file under
`docs/superpowers/plans/` with a Constitution Review section before
implementation, per the AGENTS.md gate.

## 7. Doc Updates This Plan Implies（連動文件）

- `docs/ROADMAP.md` — Now/Next/Later reorganized around these phases (done in
  the same change as this plan).
- `genesis_hosting.md` C-3 — superseded in part: single-region push uses
  Phoenix Channels, not Pub/Sub (noted inline there).
- `sosp.md` A-1/C-1/D-1 TODOs — tracked here as G3/G8/G4; tick there when the
  phases land.
- When a phase completes, update the README component status table and the
  compliance review in the same change.
