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
| `HOST` | Bind address | `127.0.0.1` (image: `0.0.0.0`) |
| `PORT` | HTTP port | `5173` (image: `8080`) |

Point `RELAY_BASE_URL` at the deployed relay in production, and add this
frontend's origin to the relay's `WEB_ALLOWED_ORIGINS`.

## Docker

```bash
docker build -t ansible-web ansible_distribution_frontend
docker run -p 8080:8080 -e RELAY_BASE_URL=https://relay.elix.cool ansible-web
```

## Deploy

Cloud Run runbook: [`../docs/deployment/cloud_run_deploy.md`](../docs/deployment/cloud_run_deploy.md) (§8 Frontend).
