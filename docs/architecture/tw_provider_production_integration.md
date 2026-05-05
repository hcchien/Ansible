# TW Provider Production Integration

## Endpoint Sequence

```text
App -> Issuer: POST /api/v1/vc/tw/start {did,email}
Issuer -> SessionStore: create single-use auth state
Issuer -> App: {offer_id,state,authorization_url,expires_at}
App -> TW Provider: open authorization_url
TW Provider -> Issuer: POST /api/v1/vc/tw/callback
Issuer -> ProofVerifier: normalize and verify assertion
Issuer -> SessionStore: consume state and replay_id
Issuer -> SessionStore: store subject commitment only
App -> Issuer: GET /api/v1/vc/tw/status/{offer_id}
Issuer -> App: {status: pending|verified|not_found}
App -> Issuer: POST /api/v1/vc/tw/issue {did,email,offer_id}
Issuer -> SessionStore: consume verified commitment
Issuer -> App: {vc}
```

## Environment Variables

- `TW_PROVIDER_SESSION_STORE_PATH`: JSON session store path. Required outside mock mode.
- `TW_PROVIDER_AUTH_URL`: provider authorization endpoint. Required outside mock mode.
- `TW_PROVIDER_ADAPTER_MODE`: verifier adapter mode. Required outside mock mode. Supported values:
  - `contract`: HMAC contract verifier for CI and staging-only provider-shape tests.
  - `production`: fail-closed placeholder until approved TW provider API and trust-anchor validation are implemented.
- `TW_PROVIDER_SHARED_SECRET`: HMAC contract verifier secret. Required when `TW_PROVIDER_ADAPTER_MODE=contract`.
- `TW_PROVIDER_AUDIENCE`: expected provider audience binding. Required when `TW_PROVIDER_ADAPTER_MODE=contract`.
- `TW_PROVIDER_PRODUCTION_TRUST_ANCHORS`: comma-separated production trust-anchor identifiers. Required when `TW_PROVIDER_ADAPTER_MODE=production`, but not sufficient to enable production issuance yet.
- `TW_PROVIDER_PRODUCTION_AUDIENCE`: production provider audience binding. Required when `TW_PROVIDER_ADAPTER_MODE=production`, but not sufficient to enable production issuance yet.
- `TW_PROVIDER_SESSION_TTL_SECONDS`: auth session TTL. Defaults to `300`.

When `MOCK_MODE=true`, the server wires a file-backed store in `os.TempDir()`,
uses `TW_PROVIDER_ADAPTER_MODE=contract` with a dev-only verifier secret, and
exposes the TW flow for local app tests.

Production deployments must set `TW_PROVIDER_ADAPTER_MODE=production`. Until the
approved provider API, callback fixture, and trust-anchor verification are
implemented, this mode intentionally fails closed during issuer startup. The
server must not silently fall back to the HMAC contract verifier in production
mode.

## Callback Field Mapping

- `state`: issuer-generated auth state from `/tw/start`.
- `replay_id`: provider assertion ID, transaction ID, nonce, or equivalent single-use callback identifier. If omitted by the contract verifier, `state` is used.
- `provider_subject`: normalized stable provider subject claim. It is used only inside issuer memory to derive a commitment.
- `assurance_context`: provider assurance or certificate context. Defaults to `tw_natural_person_certificate` for the local contract verifier.
- `audience`: must match `TW_PROVIDER_AUDIENCE`.
- `expires_at`: provider assertion expiry in RFC 3339.
- `assertion`: signed provider assertion payload.
- `signature`: provider proof signature. The local contract verifier expects HMAC-SHA256 over the exact `assertion` string.

## Replay And Session Retention

Auth sessions are single-use and expire after `TW_PROVIDER_SESSION_TTL_SECONDS`.
The issuer persists consumed `replay_id` values until their expiry window ends.
Verified sessions store only the derived subject commitment and are consumed once
when `/tw/issue` succeeds or rejects the bound DID/email.

For single-node deployments, `TW_PROVIDER_SESSION_STORE_PATH` must be on
persistent encrypted storage so replay state survives restarts.

## Privacy Logging Rules

Do not log or store these values:

- `assertion`
- `provider_subject`
- raw national ID
- legal name
- certificate serial

Application UI, wallet storage, relay sync, and VC payloads must never persist
raw provider assertions or government identity fields. Only the issuer-side
subject commitment may be stored after callback verification.

## External Sandbox Gate

CI may run without partner credentials. In that case the external provider test
must skip with the missing environment variable names. When credentials are
present, the sandbox test must execute a partner-approved callback fixture and
must fail until that fixture is implemented.
