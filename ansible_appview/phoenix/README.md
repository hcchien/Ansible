# ansible_appview (Elixir/Phoenix) — AppView Component D (Phase B)

The scalable read side of the following feed. It consumes the relay op stream,
folds it into a PostgreSQL projection indexed by `author_did` + `log_id`, and
serves per-follower timelines (fan-out-on-read) so clients stop pulling the
global firehose.

## Prerequisites

- Elixir ≥ 1.19 / Erlang OTP ≥ 27 (see `mix.exs`)
- PostgreSQL
- A running relay to ingest from (`RELAY_BASE_URL`)

## Local development

```bash
cd ansible_appview/phoenix
mix deps.get
mix ecto.create
mix ecto.migrate
mix run --no-halt          # listens on :4003 in dev; polls RELAY_BASE_URL
```

### Tests

```bash
# Requires PostgreSQL; the test DB is ansible_appview_test.
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.create
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix ecto.migrate
POSTGRES_USER="$USER" POSTGRES_PASSWORD=postgres MIX_ENV=test mix test
```

## Environment variables (prod / runtime.exs)

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Projection database (required) |
| `RELAY_BASE_URL` | Relay to ingest the op delta from (required) |
| `PORT` | HTTP port (default `8080`) |
| `POOL_SIZE` | Primary DB pool size |
| `INGEST_INTERVAL_MS` | Relay poll interval |
| `DATABASE_REPLICA_URL` | Optional read replica for timeline reads |
| `REDIS_URL` | Optional shared building-block cache (else in-process ETS) |

Run the ingest poller on a **single** instance (one firehose consumer); the
timeline API can run on many. See
[`../../docs/deployment/scaling_operations.md`](../../docs/deployment/scaling_operations.md).

## Endpoints

- `GET /health`
- `POST /api/v1/timeline` — body `{dids, cursor?, limit?}` (following timeline)
- `GET /api/v1/board-feed?board_id=&cursor=`
- `GET /metrics` — Prometheus metrics (see below)

## Metrics

Prometheus metrics are exposed at `GET /metrics` (plain text, outside `/api/*`
so the protocol-version plug never gates the scrape). The registry is a
dependency-free ETS-backed module (`AnsibleAppview.Metrics`) supervised in
`application.ex`; a periodic poller samples the ingest-lag gauge. Series:

| Metric | Type | Labels | Source |
|---|---|---|---|
| `appview_ingest_folds_total` | counter | — | signature-valid ops folded (`Ingest.Folder.apply_ops`) |
| `appview_ingest_lag_seconds` | gauge | — | now − newest folded op timestamp, polled |
| `appview_timeline_requests_total` | counter | `kind` (`following`/`home`/`board`) | timeline reads |
| `appview_timeline_request_duration_seconds` | histogram | `kind` | timeline latency |
| `appview_discovery_requests_total` | counter | `kind` (`explore`/`suggest`/`search`/`search_actors`) | discovery reads |
| `appview_discovery_request_duration_seconds` | histogram | `kind` | discovery latency |

`appview_ingest_lag_seconds` is the Phase 3 ingest-lag exit metric; ingest
fold count backs the ingest-rate criteria.

## Migrations / rebuild (release)

```bash
bin/ansible_appview eval "AnsibleAppview.Release.migrate()"
bin/ansible_appview eval "AnsibleAppview.Release.rebuild()"   # re-fold from cursor 0
```

## Docker

```bash
docker build -t ansible-appview ansible_appview/phoenix
```

## Deploy

Cloud Run runbook (optional, load-triggered):
[`../../docs/deployment/cloud_run_deploy.md`](../../docs/deployment/cloud_run_deploy.md) (§8a).
Design: [`../../docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md`](../../docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md).
