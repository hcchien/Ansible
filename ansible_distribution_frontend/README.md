# ansible_distribution_frontend — Public Forum Web Frontend

A dependency-free Node ES-module SPA (`server.mjs` + `src/`) that renders the
public Forum Host views and the app-approved DID web-session flow. The browser
talks only to this origin; the server proxies `/api/*` to the relay, which keeps
the `SameSite=Strict` web-session cookie working.

## Prerequisites

- Node ≥ 22 (no npm dependencies; uses the Node standard library only)
- A reachable relay for `/api/*` (`RELAY_BASE_URL`)

## Local development

```bash
cd ansible_distribution_frontend
npm run dev                # node server.mjs — listens on :5173, proxies /api/* to RELAY_BASE_URL
```

### Tests

```bash
npm test                   # runs test/*.test.mjs
```

## Environment variables

| Var | Purpose | Default |
|---|---|---|
| `RELAY_BASE_URL` | Relay the server proxies `/api/*` to | `http://localhost:4001` |
| `PUBLIC_RELAY_ORIGIN` | Public relay origin embedded in app-login QR payloads | `RELAY_BASE_URL` |
| `APPVIEW_URL` | AppView the server proxies curated external content (`GET /api/v1/boards/:id/external`) to | `RELAY_BASE_URL` |
| `HOST` | Bind address | `127.0.0.1` (image: `0.0.0.0`) |
| `PORT` | HTTP port | `5173` (image: `8080`) |

Point `RELAY_BASE_URL` at the deployed relay in production, and add this
frontend's origin to the relay's `WEB_ALLOWED_ORIGINS`.
Set `PUBLIC_RELAY_ORIGIN` when the proxy upstream is not the same public origin
that the Elix app should call from scanned login QR codes.

`APPVIEW_URL` is a separate read service for curated, never-verified federated
("站外 / fediverse") content. Only `GET /api/v1/boards/:id/external` is routed
there; all other `/api/*` traffic still goes to the relay. It defaults to
`RELAY_BASE_URL` so single-process dev works without extra config; set it
explicitly once the AppView is a distinct origin. An AppView outage degrades
gracefully — the board page still renders, the external section just shows an
empty/unavailable state.

## Metrics

Prometheus metrics are exposed at `GET /metrics` (plain text). The registry is a
tiny dependency-free counter set in `server.mjs` (no `prom-client`, keeping the
frontend zero-runtime-dep); the `/metrics` scrape is not self-counted. Series:

| Metric | Type | Labels | Source |
|---|---|---|---|
| `frontend_requests_total` | counter | `kind` (`asset`/`proxy`/`health`) | every served request |
| `frontend_upstream_requests_total` | counter | — | relay calls attempted via the `/api/*` proxy |
| `frontend_upstream_errors_total` | counter | `reason` (`transport`/`upstream_5xx`) | failed relay calls |

## Docker

```bash
docker build -t ansible-web ansible_distribution_frontend
docker run -p 8080:8080 -e RELAY_BASE_URL=https://relay.elix.cool ansible-web
```

## Deploy

Cloud Run runbook: [`../docs/deployment/cloud_run_deploy.md`](../docs/deployment/cloud_run_deploy.md) (§8 Frontend).
