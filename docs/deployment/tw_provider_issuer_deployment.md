# TW Provider Issuer Deployment

## Scope

This document covers deploying the Go issuer with the production-shaped TW
provider flow. The real TW provider API is not wired yet. Production adapter
mode intentionally fails closed until approved provider API details, callback
fixtures, and trust-anchor verification are implemented.

## Required Core Environment

- `ISSUER_DID`: issuer DID, for example `did:web:issuer.trisaura.io`.
- `ISSUER_URL`: public issuer base URL used in VC IDs.
- `ISSUER_PRIVATE_KEY_HEX`: issuer Ed25519 private key hex.
- `SUBJECT_COMMITMENT_PEPPER`: secret pepper for subject commitment HMACs.
- `PORT`: HTTP port. Defaults to `4002`.
- `OTP_TTL_SECONDS`: Email OTP TTL. Defaults to `300`.
- `VC_TTL_DAYS`: VC TTL. Defaults to `90`.
- `MOCK_MODE`: set `true` only for local/dev test mode.

## TW Provider Environment

- `TW_PROVIDER_SESSION_STORE_PATH`: durable JSON session store path.
- `TW_PROVIDER_AUTH_URL`: provider authorization URL.
- `TW_PROVIDER_ADAPTER_MODE`: verifier adapter mode. Required outside mock mode.
  - `contract`: HMAC verifier for CI and staging provider-shape tests.
  - `production`: fail-closed placeholder until the real adapter is implemented.
- `TW_PROVIDER_SHARED_SECRET`: required when `TW_PROVIDER_ADAPTER_MODE=contract`.
- `TW_PROVIDER_AUDIENCE`: required when `TW_PROVIDER_ADAPTER_MODE=contract`.
- `TW_PROVIDER_PRODUCTION_TRUST_ANCHORS`: comma-separated trust-anchor IDs for
  future production mode. Required for production mode, but not sufficient to
  enable issuance yet.
- `TW_PROVIDER_PRODUCTION_AUDIENCE`: future production audience binding.
- `TW_PROVIDER_SESSION_TTL_SECONDS`: auth session TTL. Defaults to `300`.
- `TW_PROVIDER_RETENTION_SECONDS`: expired session/replay retention window before
  cleanup. Defaults to `86400`.

## Startup Behavior

In `MOCK_MODE=true`, the issuer defaults to the `contract` adapter with local
dev values when TW provider env vars are absent.

Outside mock mode:

- `TW_PROVIDER_ADAPTER_MODE` must be set explicitly.
- `contract` mode requires `TW_PROVIDER_SHARED_SECRET` and
  `TW_PROVIDER_AUDIENCE`.
- `production` mode fails startup until the production verifier is implemented.
- Startup runs session store cleanup once to remove expired auth sessions,
  verified sessions, and replay IDs beyond the retention window.

## Health And Readiness

- `GET /healthz` returns `200` with `{"status":"ok"}` when the process is alive.
- `GET /readyz` returns `200` when the TW provider flow is configured.
- `GET /readyz` returns `503` with `{"status":"not_ready","tw_provider":"unconfigured"}` when the TW provider flow is not configured.

Readiness responses must not include secrets, session store paths, callback
payloads, or provider authorization URL query values.

## Audit-Safe Counters

The issuer tracks structured in-memory counters for TW provider callback
outcomes:

- `tw_callback_verified`
- `tw_callback_replay`
- `tw_callback_state_mismatch`
- `tw_callback_expired_session`
- `tw_callback_missing_provider_proof`
- `tw_callback_invalid_provider_proof`
- `tw_callback_session_error`

Counters store only event names and counts. They must not store callback bodies,
DIDs, email addresses, `assertion`, `provider_subject`, national IDs, legal
names, certificate serials, or IP addresses.

## Privacy Rules

Do not log or persist:

- provider callback body
- `assertion`
- `provider_subject`
- raw national ID
- legal name
- birth date
- certificate serial

The issuer may persist only issuer auth state, replay IDs, verified subject
commitments, and issued VC metadata needed for duplicate prevention.
