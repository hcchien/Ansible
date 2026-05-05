# Issuer Production Adapter Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TW provider production adapter boundary that fails closed until real partner API/trust-anchor details are available.

**Architecture:** Keep HTTP callback handling dependent only on `provider.ProofVerifier`. Add a provider-level adapter factory that can construct the current HMAC contract verifier or reject production mode explicitly. Move server env interpretation into a testable config builder so production never silently falls back to contract verification.

**Tech Stack:** Go 1.22, standard library tests, existing `ansible_issuer/go/internal/provider` and `cmd/server` wiring.

---

## Task 1: Provider Adapter Boundary

**Files:**
- Create: `ansible_issuer/go/internal/provider/verifier_adapter.go`
- Create: `ansible_issuer/go/internal/provider/verifier_adapter_test.go`

- [ ] Write failing tests for contract adapter construction and production fail-closed behavior.
- [ ] Implement `VerifierAdapterMode`, `VerifierAdapterConfig`, and `NewProofVerifierAdapter`.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./internal/provider`.
- [ ] Commit `feat: add TW verifier adapter boundary`.

## Task 2: Server Fail-Closed Wiring

**Files:**
- Modify: `ansible_issuer/go/cmd/server/main.go`
- Create: `ansible_issuer/go/cmd/server/main_test.go`
- Modify: `docs/architecture/tw_provider_production_integration.md`

- [ ] Write failing tests for TW provider env parsing:
  - mock mode defaults to contract adapter;
  - non-mock mode requires `TW_PROVIDER_ADAPTER_MODE`;
  - production mode fails closed.
- [ ] Extract testable TW provider config construction from `configureTWProvider`.
- [ ] Wire `NewProofVerifierAdapter` instead of direct `NewContractProofVerifier`.
- [ ] Update docs with `TW_PROVIDER_ADAPTER_MODE` and production fail-closed notes.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./cmd/server ./internal/provider`.
- [ ] Commit `feat: fail closed without TW production adapter`.

## Task 3: Verification

**Files:**
- Modify as needed based on verification.

- [ ] Run `gofmt -w` on changed Go files.
- [ ] Run `go test -count=1 -ldflags=-linkmode=external ./...` in `ansible_issuer/go`.
- [ ] Run privacy scan:

```bash
rg -n "nationalId|legalName|birthDate|certificateSerial|provider_subject|assertion" ansible_issuer/go docs/architecture/tw_provider_production_integration.md
```

Expected: contract docs/tests may mention callback field names; production wiring must not log or store raw assertion/provider subject.
