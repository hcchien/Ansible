# TW Provider Operational Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the Go issuer TW provider flow for deployment without wiring a real TW provider API.

**Architecture:** Keep provider verification behind `ProofVerifier` and session persistence behind `SessionStore`. Add cleanup to session stores, keep startup config parsing testable, add in-memory audit-safe event counters, and expose health/readiness endpoints that reveal only configured/unconfigured state.

**Tech Stack:** Go 1.22 standard library HTTP server/tests, existing `ansible_issuer/go/internal/api`, `internal/provider`, and `cmd/server`.

---

## Task 1: Deployment Document

**Files:**
- Create: `docs/deployment/tw_provider_issuer_deployment.md`
- Create: `docs/superpowers/specs/2026-05-06-tw-provider-operational-hardening-design.md`

- [ ] Document core issuer env vars.
- [ ] Document TW provider adapter modes and fail-closed production behavior.
- [ ] Document session store retention cleanup.
- [ ] Document health/readiness endpoints.
- [ ] Document audit-safe counters and prohibited raw fields.
- [ ] Commit `docs: add TW provider issuer deployment guide`.

## Task 2: Session Store Retention Cleanup

**Files:**
- Modify: `ansible_issuer/go/internal/provider/session_store.go`
- Modify: `ansible_issuer/go/internal/provider/file_session_store.go`
- Modify: `ansible_issuer/go/internal/provider/memory_session_store.go`
- Modify: `ansible_issuer/go/internal/provider/session_store_test.go`

- [ ] Write failing tests that cleanup removes expired auth sessions, verified sessions, and replay IDs after retention.
- [ ] Add `CleanupExpired(retention time.Duration) error` to `SessionStore`.
- [ ] Implement cleanup for file and memory stores using each store's `now`.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./internal/provider`.
- [ ] Commit `feat: clean up expired TW provider sessions`.

## Task 3: Startup Config Hardening

**Files:**
- Modify: `ansible_issuer/go/cmd/server/main.go`
- Modify: `ansible_issuer/go/cmd/server/main_test.go`

- [ ] Write failing tests for `TW_PROVIDER_RETENTION_SECONDS` default/override and startup cleanup.
- [ ] Add retention parsing to the testable TW provider config builder.
- [ ] Run cleanup after file store creation and before handler configuration.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./cmd/server`.
- [ ] Commit `feat: harden TW provider startup config`.

## Task 4: Health And Readiness Endpoints

**Files:**
- Modify: `ansible_issuer/go/internal/api/handler.go`
- Modify: `ansible_issuer/go/internal/api/handler_test.go`

- [ ] Write failing tests for `GET /healthz`, configured `GET /readyz`, and unconfigured `GET /readyz`.
- [ ] Register health/readiness endpoints.
- [ ] Return only status and `tw_provider` configured/unconfigured.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./internal/api`.
- [ ] Commit `feat: expose issuer health readiness endpoints`.

## Task 5: Audit-Safe Counters

**Files:**
- Create: `ansible_issuer/go/internal/api/audit_counters.go`
- Create: `ansible_issuer/go/internal/api/audit_counters_test.go`
- Modify: `ansible_issuer/go/internal/api/handler.go`
- Modify: `ansible_issuer/go/internal/api/tw_provider_flow_test.go`
- Modify: `ansible_issuer/go/internal/api/privacy_test.go`

- [ ] Write failing tests for in-memory counters and TW callback outcome increments.
- [ ] Implement `AuditCounters` and `MemoryAuditCounters`.
- [ ] Add optional counters to `TWProviderConfig`.
- [ ] Increment counters by event name only in `twCallback`.
- [ ] Assert privacy tests do not see callback body fields in responses.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./internal/api`.
- [ ] Commit `feat: add audit-safe TW provider counters`.

## Task 6: Full Verification

**Files:**
- Modify as needed based on verification.

- [ ] Run `gofmt -w` on changed Go files.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./...` in `ansible_issuer/go`.
- [ ] Run privacy scan:

```bash
rg -n "nationalId|legalName|birthDate|certificateSerial|provider_subject|assertion" ansible_issuer/go docs/deployment docs/architecture/tw_provider_production_integration.md
```

Expected: docs/tests/provider verifier internals may mention callback field names; health/readiness, startup config, counters, and logs must not store or emit raw callback fields.
