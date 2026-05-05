# TW Provider Operational Hardening Design

## Scope

Harden the existing Go issuer TW provider flow for deployment readiness without
integrating a real TW provider API. The work covers deployment documentation,
session store cleanup, startup config tests, audit-safe counters, and health /
readiness endpoints.

## Design

The issuer keeps using the existing `provider.SessionStore` and
`provider.ProofVerifier` boundaries. Session stores gain a cleanup capability
that removes expired auth sessions, verified sessions, and replay IDs after a
retention window. Startup builds TW provider config through the existing
testable env builder and runs cleanup once after opening the file-backed store.

The API handler gains a small in-memory `AuditCounters` dependency. TW callback
outcomes increment structured event names only. The counter API does not accept
or store callback bodies, DIDs, emails, assertions, provider subjects, IP
addresses, or government identity fields.

The HTTP mux exposes:

- `GET /healthz`: process liveness, always `200` when registered.
- `GET /readyz`: readiness with `tw_provider=configured|unconfigured`; returns
  `503` when the TW provider flow is not configured.

## Deployment Document

`docs/deployment/tw_provider_issuer_deployment.md` describes required env vars,
adapter mode behavior, fail-closed production mode, session retention cleanup,
health/readiness responses, and audit-safe counter guarantees.

## Testing

Provider tests cover memory and file cleanup behavior. Server tests cover startup
config defaults and required envs. API tests cover health/readiness responses and
counter increments for verified, replay, state mismatch, and invalid proof
callback outcomes. Privacy tests ensure callback body fields are not emitted.
