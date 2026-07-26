# ansible_relay/phoenix — Elixir/Phoenix Relay And Forum Host MVP

> **Status: current MVP implementation.** This service is no longer a future
> placeholder. It currently hosts co-located Elix Relay and Forum Host API
> surfaces for development and first deployment, while keeping the route,
> storage, and authorization contracts separate so a later Cloud Run/service
> split does not require an API redesign.

## Local install and run

**Prerequisites:** Elixir ≥ 1.19 / OTP ≥ 27 (see `mix.exs`), a Rust toolchain
(for the `sig_verifier_nif` Ed25519 NIF, built on first compile), PostgreSQL.

```bash
cd ansible_relay/phoenix
mix deps.get
mix ecto.create
mix ecto.migrate
mix run --no-halt          # listens on :4001 in dev
```

### Tests

```bash
# Requires PostgreSQL; test DB is ansible_relay_test.
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.create
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.migrate
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix test
```

### Key environment variables (prod / runtime.exs)

| Var | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection (required) |
| `ISSUER_DID`, `ISSUER_PUBLIC_KEY_HEX` | Trusted VC issuer (public half of the issuer key) |
| `RELAY_ORIGIN`, `FORUM_HOST_BASE_URL` | Public origins (not localhost in prod) |
| `WEB_ALLOWED_ORIGINS` | Frontend origin(s) for credentialed CORS |
| `PORT`, `POOL_SIZE`, `DATABASE_SSL` | HTTP port (`8080` in the image) / DB pool / TLS |
| `REDIS_URL` | Optional shared cross-instance abuse limiter |
| `LIBCLUSTER_HOSTS` | Optional Erlang clustering (GKE) |

Migrations on a release image (no `mix`): `bin/ansible_relay eval "AnsibleRelay.Release.migrate()"`.
Full deploy: [`../../docs/deployment/cloud_run_deploy.md`](../../docs/deployment/cloud_run_deploy.md);
scaling flags: [`../../docs/deployment/scaling_operations.md`](../../docs/deployment/scaling_operations.md).

## Current API Surface

Implemented route groups include:

- Relay identity and DID anchoring APIs.
- Relay discovery: `GET /api/v1/discovery`.
- Forum Host metadata and hosted-board APIs:
  - `GET /api/v1/forum-host`
  - `GET /api/v1/forum-host/boards`
  - `POST /api/v1/forum-host/boards`
  - `POST /api/v1/forum-host/web/threads`
- Web sessions:
  - `POST /api/v1/web-sessions/challenges`
  - `GET /api/v1/web-sessions/challenges/:id`
  - `POST /api/v1/web-sessions/approve`
  - `POST /api/v1/web-sessions/reject`
  - `GET /api/v1/web-sessions/me`
  - `GET /api/v1/web-sessions`
  - `POST /api/v1/web-sessions/revoke`
- Publication intent, ActivityPub MVP, XRPC compatibility, reputation, and
  messenger APIs.

Browser web-session auth is httpOnly-cookie first. The relay sets
`trisaura_session` on approved challenge polling and accepts that cookie for
scoped Forum Host web writes; bearer tokens remain a compatibility path for
server/API callers. App-originated create-board writes use DID signed intents
instead of web-session auth.

## Metrics

Prometheus metrics are exposed at `GET /metrics` (plain text, outside `/api/*`
so the protocol-version plug never gates the scrape). The registry is a
dependency-free ETS-backed module (`AnsibleRelay.Metrics`) supervised in
`application.ex`; a periodic poller samples gauges. Series:

| Metric | Type | Labels | Source |
|---|---|---|---|
| `relay_op_ingest_total` | counter | `entity_type`, `op_type` | accepted op ingest (`OpsController.ingest`) |
| `relay_op_table_rows` | gauge | — | `ops` table row count, polled |
| `relay_delta_requests_total` | counter | — | `GET /api/v1/ops/delta` |
| `relay_delta_request_duration_seconds` | histogram | — | delta-pull latency |
| `relay_signature_verifications_total` | counter | `result` (`pass`/`fail`) | op Ed25519 verification |
| `relay_abuse_rejections_total` | counter | `subject_type` | abuse-limiter rejections (`did` wired; `peer` TODO Phase 3) |
| `relay_wake_sends_total` | counter | `category` | push wake-scheduler sends |
| `relay_reports_total` | counter | `rail` (`signed_intent`/`web_session`) | forum-host report intake |

These back the later phases' exit criteria (op-table growth, delta-poll QPS,
signature pass/reject, delivery/wake queue depth). Phase 3's delivery-queue and
peer-abuse gauges will be added against the same module as those paths land.

## 對應 V1.1 組件

- **Comp C**: Carrier-Grade Relay / Genesis Relay
- **Forum Host MVP**: co-located hosted-board discovery, board creation, and
  scoped web thread creation.
- **Comp D / AppView**: implemented as a separate service in
  [`../../ansible_appview/phoenix`](../../ansible_appview/phoenix) — it polls
  this relay's op delta endpoint and serves the scalable following/home feed.

Genesis Hosting reference: [`../../docs/architecture/genesis_hosting.md`](../../docs/architecture/genesis_hosting.md).
Security launch checklist: [`../../docs/security/sosp.md`](../../docs/security/sosp.md).

## Historical Target Structure

The umbrella-style structure below is a target direction, not the current file
layout. The current code is a single Phoenix app under this directory.

```
ansible_relay/phoenix/
├── apps/
│   ├── relay/          # Comp C: connection manager, ETS DID cache, GCS blob handler
│   │   ├── lib/relay/
│   │   │   ├── cluster.ex              # libcluster topology + PubSub
│   │   │   ├── presence.ex             # Phoenix Presence: users + verified status
│   │   │   ├── connection_manager.ex   # GenStage, backpressure
│   │   │   ├── identity_cache.ex       # ETS: Verified DID → expiry
│   │   │   ├── zkp_key_registry.ex     # pinned circuit VK versions
│   │   │   ├── gossipsub_topic.ex      # /ansible/ops/v1 topic validation
│   │   │   ├── gossip_enforcer.ex      # Gossipsub peer scoring / disconnects
│   │   │   ├── abuse_detector.ex       # Token Bucket rate limiting
│   │   │   ├── log_redactor.ex         # IP/DID separation for ops logs
│   │   │   ├── binary_stream.ex        # Protobuf CrdtOp decode + validation
│   │   │   ├── pubsub_forwarder.ex     # GCP Pub/Sub handoff to Forum
│   │   │   ├── blob_handler.ex         # Oban job → GCS upload
│   │   │   └── sig_verifier.ex         # Rustler NIF bridge
│   │   └── ...
│   └── aggregator/     # Comp D: Op verifier, materialized views, LiveView
│       ├── lib/aggregator/
│       │   ├── pubsub_consumer.ex      # GCP Pub/Sub ingest from Relay
│       │   ├── op_verifier.ex          # Rustler NIF → Rust Ed25519 verify
│       │   ├── forum_engine.ex         # CRDT fold → PostgreSQL
│       │   ├── snapshot_exporter.ex    # signed snapshots for new hosts
│       │   ├── seo_renderer.ex         # crawlable public HTML
│       │   └── forum_live.ex           # Phoenix LiveView
│       └── ...
├── config/
├── mix.exs
└── ...
```

## 關鍵技術依賴

目前 Phoenix MVP 的 `mix.exs` 只包含已落地的 HTTP、JSON、資料庫、和簽章驗證依賴。叢集、GCS、Pub/Sub、Presence、以及背景任務仍屬於目標部署能力，不能視為目前已啟用。

### Current MVP

| 功能 | 套件 |
|------|------|
| HTTP 伺服器 | `plug` + `bandit` |
| JSON | `jason` |
| 身分狀態快取 | `:ets` (built-in) |
| Rust 簽章驗證 | `rustler` (NIF) |
| 資料庫 | `ecto` + `postgrex` (Cloud SQL) |

### Target / Not Yet Implemented

| 功能 | 目標依賴 |
|------|----------|
| 非同步任務（GCS 上傳）| `oban` |
| 物件儲存 | `goth` + `google_api_storage` (GCS) |
| 叢集拓撲 | `libcluster` |
| 使用者連線狀態 | `phoenix_presence` |
| Relay → Forum / AppView 串流 | GCP Pub/Sub |

## ETS Identity Cache / Challenge 設計

```elixir
# 表名: :verified_did_cache
# Key:   DID string  (e.g. "did:key:z6Mk...")
# Value: {public_key_hex, verified_at, expires_at}

# 表名: :identity_challenges
# Key:   DID string
# Value: {challenge, issued_at, expires_at}
#
# POST /api/v1/identity/challenge:
:ets.insert(:identity_challenges, {did, challenge_entry})

# POST /api/v1/identity/anchor:
# - verify challenge_signature
# - consume challenge exactly once

:ets.new(:verified_did_cache, [:set, :public, :named_table, read_concurrency: true])
:ets.new(:identity_challenges, [:set, :public, :named_table])

# Phase 1 完成後寫入:
:ets.insert(:verified_did_cache, {did, {pubkey_hex, verified_at, expires_at}})

# Phase 2 每次簽章驗證:
case :ets.lookup(:verified_did_cache, did) do
  [{^did, {pubkey_hex, _verified, expires}}] when expires > now -> verify_sig(pubkey_hex, sig)
  _ -> {:error, :did_not_verified}
end
```

## Rustler NIF 簽章驗證

```rust
// native/relay_nif/src/lib.rs
#[rustler::nif]
fn verify_ed25519(pubkey_hex: &str, message: Binary, sig_hex: &str) -> bool {
    // ring::signature::UnparsedPublicKey::verify(...)
}
```

## ZKP Verification Key Pinning

Phase 1 anchoring requires both `zkp_circuit_version` and
`verification_key_hash`. The relay accepts only active entries configured under
`:zkp_verification_keys`.

```elixir
config :ansible_relay,
  zkp_verification_keys: [
    %{
      version: "passport_v1_dev",
      hash: "sha256:dev-passport-v1-placeholder",
      status: :active
    }
  ]
```

The dev hashes above never reach production: `config/runtime.exs` overrides
them at prod boot with an empty (disabled, fail-closed) registry unless
`ANSIBLE_RELAY_ZKP_VERIFICATION_KEYS` supplies audited entries as JSON
(`[{"version":"...","hash":"sha256:<64 hex>","status":"active"|"retired"}]`);
placeholder or malformed entries refuse to boot
(`AnsibleRelay.Config.ZkpVerificationKeys`). Keep retired keys configured only
for explicit migration windows.

## Gossipsub Topics

Canonical Op topics follow:

```text
/ansible/ops/v1/{network}/{scope}
```

Reference: [`../../docs/protocol/gossipsub_topics.md`](../../docs/protocol/gossipsub_topics.md).

Production public Ops use:

```text
/ansible/ops/v1/mainnet/global
```

## Deployment Direction

Current local/dev deployment runs the Phoenix service as one process. The
planned production boundary is separate Cloud Run services and databases for:

- Elix Relay API + Relay DB.
- Forum Host API + Forum Host DB.
- Distribution frontend.

Until that split exists, docs and diagrams should describe the service as
co-located MVP, not as a completed GKE/AppView deployment.

### Database Migrations In Production

The production image is built with `mix release`, so `mix ecto.migrate` is not
available at runtime. Run migrations against a deployed release (or as a one-off
Cloud Run Job using the same image) with:

```bash
bin/ansible_relay eval "AnsibleRelay.Release.migrate()"
```

See `AnsibleRelay.Release` (`lib/ansible_relay/release.ex`) for migrate and
rollback tasks. Run `migrate` after deploying a new image before serving
traffic from it.

### ActivityPub Note Delivery

ActivityPub delivery is off by default. Production enables the verified-human,
explicit-opt-in Note slice with:

```text
ACTIVITY_PUB_DELIVERY_ENABLED=true
ACTIVITY_PUB_PUBLIC_KEY_PEM=<RSA public key PEM>
ACTIVITY_PUB_PRIVATE_KEY_PEM=<matching RSA private key PEM>
```

The first signed ActivityPub Note is the user's opt-in and exposes the
relay-owned Actor. The Relay requires the author's current reputation tier to
meet `verified_human`; credentials, nullifiers, and legal-identity fields never
enter the ActivityPub payload. Accepted Notes fan out to the Actor's stored
follower inboxes and are delivered with RSA-SHA256 HTTP Signatures.

Do not enable the public inbox in production until inbound HTTP Signature
verification and SSRF-safe remote Actor resolution are complete. Outbound Note
delivery can be exercised first with curated follower inbox rows.

## Genesis Hosting TODO

- [ ] Add `libcluster` and regional GKE topology config.
- [ ] Add Phoenix Presence for active users and verified DID status.
- [ ] Propagate verified DID cache updates across relay nodes.
- [x] Pin ZKP circuit version and Verification Key hash for Phase 1 anchoring.
- [x] Define and validate Gossipsub Op topic naming convention.
- [ ] Implement Gossipsub peer scoring and disconnect reason codes.
- [x] Implement Token Bucket abuse detection for DID Op submission.
- [ ] Implement Token Bucket abuse detection for peer invalid-message limits.
- [ ] Implement log redaction that prevents IP/DID joins in GCP logs.
- [ ] Add Protobuf binary stream handler for `CrdtOp`.
- [ ] Forward accepted Ops to GCP Pub/Sub.
- [ ] Implement Forum Pub/Sub consumer and Rustler batch verifier.
- [ ] Add PostgreSQL materialized projections and logical replication.
- [ ] Add signed snapshot exporter for third-party aggregators.
- [ ] Add rendered-content verification tools for raw Op comparison.
- [ ] Define append-only hash chain and moderation/tombstone Ops.
- [ ] Enforce double verification for Forum ingestion: valid signature and active DID anchor.
