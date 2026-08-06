# ansible_issuer (Go) — Credential Issuer

Issues W3C Verifiable Credentials (Data Integrity `eddsa-jcs-2022`) for Tris-Aura:
humanity credentials (passport NFC, TW provider, MobileMoica RP) and email
contactability credentials. Serves the issuer `did:web` document so external
verifiers can resolve the signing key.

Humanity credentials carry signed assurance dimensions rather than a single
undifferentiated result: `humanAssurance`, `uniquenessAssurance`, and the
coarse `verificationMethodClass`. Current passport NFC and Taiwan
natural-person paths issue `verified` + `strong`; phone or email control never
counts as human assurance. Raw identity and duplicate-prevention commitments
remain issuer-local and are not included in the VC.

## Prerequisites

- Go ≥ 1.25 (see `go.mod`)
- PostgreSQL (only for `DATABASE_URL` mode; not needed for mock/file mode)

## Local development

```bash
cd ansible_issuer/go

# Mock mode — no DB, no real provider; contract/mock verifiers, in-memory stores.
MOCK_MODE=true \
ISSUER_DID=did:web:issuer.localhost \
ISSUER_URL=http://localhost:4002 \
ISSUER_PRIVATE_KEY_HEX=$(openssl rand -hex 32) \
SUBJECT_COMMITMENT_PEPPER=$(openssl rand -hex 32) \
go run ./cmd/server
# listens on :4002 (PORT overrides)
```

### Tests

```bash
go build ./...
go vet ./...
go test ./...                      # unit tests (Postgres-backed tests skip)

# Include the Postgres store tests:
createdb ansible_issuer_test
ISSUER_TEST_DATABASE_URL="postgres://$USER@localhost:5432/ansible_issuer_test" go test ./...
```

## Environment variables

**Core (required outside mock mode):**

| Var | Purpose |
|---|---|
| `ISSUER_DID` | Issuer DID, e.g. `did:web:issuer.elix.cool` |
| `ISSUER_URL` | Public base URL (used in VC IDs) |
| `ISSUER_PRIVATE_KEY_HEX` | Ed25519 seed (32-byte hex), permitted only for local/non-production development. |
| `ISSUER_KMS_KEY_VERSION` | Required in production: versioned Cloud KMS `EC_SIGN_ED25519` key. Its private material is non-exportable; Cloud KMS currently provides this algorithm with software protection rather than HSM protection. |
| `SUBJECT_COMMITMENT_PEPPER` | HMAC pepper for subject commitments |
| `PORT` | HTTP port (default `4002`; the image sets `8080`) |
| `VC_TTL_DAYS`, `OTP_TTL_SECONDS` | Credential / OTP TTLs |
| `MOCK_MODE` | `true` for local/dev only |

**Durable storage** — set `DATABASE_URL` to use PostgreSQL (personhood +
provider session stores → horizontally scalable). Otherwise file-backed
(single instance): `PERSONHOOD_BINDING_STORE_PATH`, `TW_PROVIDER_SESSION_STORE_PATH`,
`MOBILEMOICA_SESSION_STORE_PATH`.

**TW provider / MobileMoica:** see
[`../../docs/deployment/tw_provider_issuer_deployment.md`](../../docs/deployment/tw_provider_issuer_deployment.md)
for `TW_PROVIDER_*` and `MOBILEMOICA_*`. Note: `production` adapter mode fails
closed until the real provider integration lands.

## Endpoints

- `GET /healthz` — liveness
- `GET /readyz` — `200` when the TW provider flow is configured, else `503`
- `GET /metrics` — Prometheus metrics (see below)
- `GET /.well-known/did.json` — issuer DID document (Multikey)
- `POST /api/v1/vc/*` — issuance flows (email, passport, TW, MobileMoica)

## Metrics

Prometheus metrics are exposed at `GET /metrics` (plain text). The registry is a
dependency-free counter set (`internal/metrics`) held on the API handler;
`Register` wraps every endpoint with request + error counting. Series:

| Metric | Type | Labels | Source |
|---|---|---|---|
| `issuer_requests_total` | counter | `endpoint` | every wrapped HTTP endpoint |
| `issuer_credentials_issued_total` | counter | `type` (`email`/`passport`/`mobilemoica_humanity`) | successful issuance |
| `issuer_errors_total` | counter | `endpoint` | handler responses with status ≥ 400 |

## Docker

```bash
docker build -t ansible-issuer ansible_issuer/go
docker run -p 8080:8080 -e MOCK_MODE=true -e ISSUER_DID=... -e ISSUER_URL=... \
  -e ISSUER_PRIVATE_KEY_HEX=... -e SUBJECT_COMMITMENT_PEPPER=... ansible-issuer
```

## Deploy

Full Cloud Run runbook: [`../../docs/deployment/cloud_run_deploy.md`](../../docs/deployment/cloud_run_deploy.md)
(§7 Issuer). Scaling flags: [`../../docs/deployment/scaling_operations.md`](../../docs/deployment/scaling_operations.md).
