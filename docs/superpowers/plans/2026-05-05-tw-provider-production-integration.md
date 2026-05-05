# TW Provider Production Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the issuer's mock-only identity proofing path with a stateful TW provider issuance flow that rejects replayed callbacks, never stores raw identity assertions, and gives the app a production-shaped start/poll/issue API.

**Architecture:** The Go issuer remains the source of truth for identity proofing. `ansible_issuer/go/internal/provider` owns authorization sessions, replay tracking, callback normalization, and provider proof verification. `ansible_issuer/go/internal/api` exposes `/api/v1/vc/tw/start`, `/api/v1/vc/tw/callback`, `/api/v1/vc/tw/status/{offer_id}`, and `/api/v1/vc/tw/issue`; the Flutter app only starts an offer, polls status, and requests issuance after the issuer has stored a verified subject commitment.

**Tech Stack:** Go 1.22 standard library HTTP server, Ed25519 issuer signing already present in `internal/vc`, Dart/Flutter app client tests, file-backed JSON persistence for single-node replay/session durability, env-gated external provider tests.

---

## Current State

Task 6 created a contract-test adapter in `ansible_issuer/go/internal/provider`:

- `MemoryStateProvider.StartAuth(offerID, state string)`
- `MemoryStateProvider.HandleCallback(map[string]string) CallbackResult`
- error codes: `callback_replay`, `state_mismatch`, `expired_session`, `missing_provider_proof`
- contract doc: `ansible_issuer/go/internal/provider/tw_identity_provider_contract.md`

The current production HTTP path still uses:

- `POST /api/v1/vc/request`
- `POST /api/v1/vc/issue`
- `provider.TwIdentityProvider.ProviderSubject(did, email)`

This plan keeps those endpoints working for mock/email OTP compatibility and adds the TW provider flow beside them.

## File Structure

- Modify: `ansible_issuer/go/internal/provider/provider.go`
  - Add production-shaped provider session and proof verifier interfaces.
- Create: `ansible_issuer/go/internal/provider/session_store.go`
  - Define `AuthSession`, `VerifiedSession`, and `SessionStore`.
- Create: `ansible_issuer/go/internal/provider/file_session_store.go`
  - Durable JSON file store for auth sessions, consumed replay IDs, and verified commitments.
- Create: `ansible_issuer/go/internal/provider/session_store_test.go`
  - Contract tests for single-use state, replay persistence, expiry, and verified commitment storage.
- Create: `ansible_issuer/go/internal/provider/proof_verifier.go`
  - Normalize and verify callback proof fields through a verifier interface.
- Create: `ansible_issuer/go/internal/provider/proof_verifier_test.go`
  - Tests for missing proof, invalid signature, wrong audience, and normalized subject output.
- Modify: `ansible_issuer/go/internal/api/handler.go`
  - Add TW provider endpoints and inject the new provider dependencies.
- Create: `ansible_issuer/go/internal/api/tw_provider_flow_test.go`
  - End-to-end HTTP tests for start, callback, status, issue, replay, mismatch, and expiry.
- Modify: `ansible_issuer/go/cmd/server/main.go`
  - Wire file-backed session store and provider verifier from environment.
- Modify: `ansible_node/app/lib/services/vc_issuer_client.dart`
  - Add TW provider start/status/issue client methods.
- Modify: `ansible_node/app/test/vc_issuer_client_test.dart`
  - Add client tests for the new endpoints.
- Create: `docs/architecture/tw_provider_production_integration.md`
  - Operational notes, env vars, callback contract, privacy logging rules, and external test setup.

## Task 1: Durable Provider Session Store

**Files:**

- Create: `ansible_issuer/go/internal/provider/session_store.go`
- Create: `ansible_issuer/go/internal/provider/file_session_store.go`
- Test: `ansible_issuer/go/internal/provider/session_store_test.go`

- [ ] **Step 1: Write failing session store tests**

Create `session_store_test.go`:

```go
package provider_test

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestFileSessionStoreConsumesStateOnce(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "provider_sessions.json"), func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	session := provider.AuthSession{
		OfferID:   "offer-1",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "state-1",
		ExpiresAt: now.Add(time.Minute),
	}
	if err := store.CreateAuthSession(session); err != nil {
		t.Fatalf("create session: %v", err)
	}

	first, err := store.ConsumeAuthState("state-1", "replay-1")
	if err != nil {
		t.Fatalf("consume first: %v", err)
	}
	if first.OfferID != "offer-1" {
		t.Fatalf("unexpected offer: %+v", first)
	}

	_, err = store.ConsumeAuthState("state-1", "replay-1")
	if err != provider.ErrReplay {
		t.Fatalf("expected replay, got %v", err)
	}
}

func TestFileSessionStoreRejectsExpiredState(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "provider_sessions.json"), func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	err = store.CreateAuthSession(provider.AuthSession{
		OfferID:   "offer-1",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "state-1",
		ExpiresAt: now.Add(-time.Second),
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	_, err = store.ConsumeAuthState("state-1", "replay-1")
	if err != provider.ErrExpiredSessionState {
		t.Fatalf("expected expired session, got %v", err)
	}
}

func TestFileSessionStorePersistsReplayAcrossRestart(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "provider_sessions.json")
	store, err := provider.NewFileSessionStore(path, func() time.Time { return now })
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	if err := store.MarkReplayIDConsumed("replay-1", now.Add(time.Hour)); err != nil {
		t.Fatalf("mark replay: %v", err)
	}

	reopened, err := provider.NewFileSessionStore(path, func() time.Time { return now })
	if err != nil {
		t.Fatalf("reopen store: %v", err)
	}
	if err := reopened.MarkReplayIDConsumed("replay-1", now.Add(time.Hour)); err != provider.ErrReplay {
		t.Fatalf("expected persisted replay rejection, got %v", err)
	}
}

func TestFileSessionStoreStoresVerifiedCommitment(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "provider_sessions.json"), func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	verified := provider.VerifiedSession{
		OfferID:           "offer-1",
		DID:               "did:plc:abcdefghijklmnop",
		Email:             "alice@example.com",
		SubjectCommitment: "commitment-1",
		VerifiedAt:        now,
		ExpiresAt:         now.Add(5 * time.Minute),
	}
	if err := store.StoreVerifiedSession(verified); err != nil {
		t.Fatalf("store verified session: %v", err)
	}

	got, err := store.GetVerifiedSession("offer-1")
	if err != nil {
		t.Fatalf("get verified session: %v", err)
	}
	if got.SubjectCommitment != "commitment-1" {
		t.Fatalf("unexpected verified session: %+v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/provider
```

Expected: FAIL because `NewFileSessionStore`, `AuthSession`, `VerifiedSession`, and store error values do not exist.

- [ ] **Step 3: Implement store interfaces and file-backed store**

Create `session_store.go`:

```go
package provider

import (
	"errors"
	"time"
)

var (
	ErrReplay              = errors.New("provider replay")
	ErrStateNotFound       = errors.New("provider state not found")
	ErrExpiredSessionState = errors.New("provider session expired")
	ErrVerifiedNotFound    = errors.New("verified session not found")
)

type AuthSession struct {
	OfferID   string    `json:"offer_id"`
	DID       string    `json:"did"`
	Email     string    `json:"email"`
	State     string    `json:"state"`
	ExpiresAt time.Time `json:"expires_at"`
	Consumed  bool      `json:"consumed"`
}

type VerifiedSession struct {
	OfferID           string    `json:"offer_id"`
	DID               string    `json:"did"`
	Email             string    `json:"email"`
	SubjectCommitment string    `json:"subject_commitment"`
	VerifiedAt        time.Time `json:"verified_at"`
	ExpiresAt         time.Time `json:"expires_at"`
	Consumed          bool      `json:"consumed"`
}

type SessionStore interface {
	CreateAuthSession(AuthSession) error
	ConsumeAuthState(state, replayID string) (AuthSession, error)
	MarkReplayIDConsumed(replayID string, expiresAt time.Time) error
	StoreVerifiedSession(VerifiedSession) error
	GetVerifiedSession(offerID string) (VerifiedSession, error)
	ConsumeVerifiedSession(offerID string) (VerifiedSession, error)
}
```

Create `file_session_store.go` with a mutex, JSON load/save, and atomic `os.Rename` writes. The persisted shape must be:

```go
type fileSessionData struct {
	AuthSessions     map[string]AuthSession     `json:"auth_sessions"`
	VerifiedSessions map[string]VerifiedSession `json:"verified_sessions"`
	ReplayIDs        map[string]time.Time       `json:"replay_ids"`
}
```

Key behavior:

- `CreateAuthSession` rejects empty `OfferID`, `State`, `DID`, or `Email`.
- `ConsumeAuthState` rejects unknown state with `ErrStateNotFound`.
- `ConsumeAuthState` rejects expired sessions with `ErrExpiredSessionState`.
- `ConsumeAuthState` rejects consumed state or consumed replay ID with `ErrReplay`.
- `MarkReplayIDConsumed` persists replay IDs and treats an unexpired duplicate as `ErrReplay`.
- `GetVerifiedSession` rejects missing, expired, or consumed sessions.
- `ConsumeVerifiedSession` marks the verified session consumed before returning it.

- [ ] **Step 4: Run provider tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/provider
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ansible_issuer/go/internal/provider/session_store.go ansible_issuer/go/internal/provider/file_session_store.go ansible_issuer/go/internal/provider/session_store_test.go
git commit -m "feat: add durable provider session store"
```

## Task 2: Provider Proof Verifier

**Files:**

- Create: `ansible_issuer/go/internal/provider/proof_verifier.go`
- Test: `ansible_issuer/go/internal/provider/proof_verifier_test.go`
- Modify: `ansible_issuer/go/internal/provider/tw_identity_provider_contract.md`

- [ ] **Step 1: Write failing proof verifier tests**

Create `proof_verifier_test.go`:

```go
package provider_test

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func signedAssertion(secret, payload string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	return hex.EncodeToString(mac.Sum(nil))
}

func TestContractProofVerifierAcceptsSignedAssertion(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})

	payload := "state-1|subject-1|trisaura-issuer|2026-05-05T12:05:00Z"
	result, err := verifier.Verify(map[string]string{
		"state":            "state-1",
		"provider_subject": "subject-1",
		"audience":         "trisaura-issuer",
		"expires_at":       "2026-05-05T12:05:00Z",
		"assertion":        payload,
		"signature":        signedAssertion("provider-secret", payload),
	})
	if err != nil {
		t.Fatalf("verify assertion: %v", err)
	}
	if result.ProviderSubject != "subject-1" || result.AssuranceContext != "tw_natural_person_certificate" {
		t.Fatalf("unexpected result: %+v", result)
	}
}

func TestContractProofVerifierRejectsMissingProof(t *testing.T) {
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
	})
	_, err := verifier.Verify(map[string]string{"state": "state-1"})
	if err != provider.ErrMissingProviderProofValue {
		t.Fatalf("expected missing proof, got %v", err)
	}
}

func TestContractProofVerifierRejectsWrongAudience(t *testing.T) {
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
	})
	payload := "state-1|subject-1|other-audience|2026-05-05T12:05:00Z"
	_, err := verifier.Verify(map[string]string{
		"state":            "state-1",
		"provider_subject": "subject-1",
		"audience":         "other-audience",
		"expires_at":       "2026-05-05T12:05:00Z",
		"assertion":        payload,
		"signature":        signedAssertion("provider-secret", payload),
	})
	if err != provider.ErrProviderAudience {
		t.Fatalf("expected wrong audience, got %v", err)
	}
}

func TestContractProofVerifierRejectsInvalidSignature(t *testing.T) {
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
	})
	_, err := verifier.Verify(map[string]string{
		"state":            "state-1",
		"provider_subject": "subject-1",
		"audience":         "trisaura-issuer",
		"expires_at":       "2026-05-05T12:05:00Z",
		"assertion":        "state-1|subject-1|trisaura-issuer|2026-05-05T12:05:00Z",
		"signature":        "bad-signature",
	})
	if err != provider.ErrProviderSignature {
		t.Fatalf("expected invalid signature, got %v", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/provider
```

Expected: FAIL because `NewContractProofVerifier` and proof verifier errors do not exist.

- [ ] **Step 3: Implement verifier interface and contract verifier**

Create `proof_verifier.go`:

```go
package provider

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"
)

var (
	ErrMissingProviderProofValue = errors.New("missing provider proof")
	ErrProviderAudience          = errors.New("invalid provider audience")
	ErrProviderSignature         = errors.New("invalid provider signature")
	ErrProviderExpiry            = errors.New("expired provider assertion")
)

type ProviderAssertion struct {
	State            string
	ReplayID         string
	ProviderSubject string
	AssuranceContext string
	ExpiresAt        time.Time
}

type ProofVerifier interface {
	Verify(callback map[string]string) (ProviderAssertion, error)
}

type ContractProofConfig struct {
	SharedSecret string
	Audience     string
	Now          func() time.Time
}
```

Implement `NewContractProofVerifier` as a deterministic verifier for staging and CI. It must:

- require `assertion`, `signature`, `provider_subject`, `audience`, and `expires_at`;
- compare `audience` to config;
- HMAC-SHA256 the exact `assertion` string with `SharedSecret`;
- parse `expires_at` using `time.RFC3339`;
- reject expired assertions;
- default `AssuranceContext` to `tw_natural_person_certificate`;
- use `replay_id` when present and fall back to `state`.

- [ ] **Step 4: Update provider contract doc**

Modify `tw_identity_provider_contract.md` to add:

```markdown
## Local Contract Verifier

The Go issuer includes an HMAC contract verifier for CI and staging-only
provider-shape tests. It validates the same normalized callback fields used by
the production adapter, but it is not a substitute for TW FidO/MOICA trust-anchor
signature verification. Production deployments must configure a provider adapter
that validates partner-issued signatures and audience binding.
```

- [ ] **Step 5: Run provider tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/provider
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ansible_issuer/go/internal/provider/proof_verifier.go ansible_issuer/go/internal/provider/proof_verifier_test.go ansible_issuer/go/internal/provider/tw_identity_provider_contract.md
git commit -m "feat: add TW provider proof verifier boundary"
```

## Task 3: TW Provider HTTP Flow

**Files:**

- Modify: `ansible_issuer/go/internal/api/handler.go`
- Test: `ansible_issuer/go/internal/api/tw_provider_flow_test.go`

- [ ] **Step 1: Write failing HTTP flow tests**

Create `tw_provider_flow_test.go`:

```go
package api_test

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/api"
	"github.com/trisaura/ansible_issuer/internal/provider"
)

func signProviderAssertion(secret, payload string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	return hex.EncodeToString(mac.Sum(nil))
}

func newTWHandler(t *testing.T, now time.Time) *api.Handler {
	t.Helper()
	h := newTestHandler(t)
	store := provider.NewMemorySessionStore(func() time.Time { return now })
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})
	h.ConfigureTWProvider(api.TWProviderConfig{
		SessionStore: store,
		Verifier:     verifier,
		BaseAuthURL:  "https://provider.example/authorize",
		TTL:          5 * time.Minute,
	})
	return h
}

func TestTWProviderFlowIssuesCredentialAfterVerifiedCallback(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)

	start := call(h, http.MethodPost, "/api/v1/vc/tw/start", map[string]any{
		"did": testDID, "email": testEmail,
	})
	if start.Code != http.StatusOK {
		t.Fatalf("start failed: %d %s", start.Code, start.Body)
	}
	startBody := bodyJSON(t, start)
	offerID := startBody["offer_id"].(string)
	state := startBody["state"].(string)

	payload := state + "|subject-1|trisaura-issuer|2026-05-05T12:05:00Z"
	callback := call(h, http.MethodPost, "/api/v1/vc/tw/callback", map[string]any{
		"state":            state,
		"provider_subject": "subject-1",
		"audience":         "trisaura-issuer",
		"expires_at":       "2026-05-05T12:05:00Z",
		"assertion":        payload,
		"signature":        signProviderAssertion("provider-secret", payload),
	})
	if callback.Code != http.StatusOK {
		t.Fatalf("callback failed: %d %s", callback.Code, callback.Body)
	}

	status := call(h, http.MethodGet, "/api/v1/vc/tw/status/"+offerID, nil)
	if bodyJSON(t, status)["status"] != "verified" {
		t.Fatalf("expected verified status, got %s", status.Body)
	}

	issue := call(h, http.MethodPost, "/api/v1/vc/tw/issue", map[string]any{
		"did": testDID, "email": testEmail, "offer_id": offerID,
	})
	if issue.Code != http.StatusOK {
		t.Fatalf("issue failed: %d %s", issue.Code, issue.Body)
	}
	if _, ok := bodyJSON(t, issue)["vc"].(map[string]any); !ok {
		t.Fatalf("expected vc response, got %s", issue.Body)
	}
}

func TestTWProviderCallbackReplayRejected(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)
	start := call(h, http.MethodPost, "/api/v1/vc/tw/start", map[string]any{
		"did": testDID, "email": testEmail,
	})
	state := bodyJSON(t, start)["state"].(string)
	payload := state + "|subject-1|trisaura-issuer|2026-05-05T12:05:00Z"
	body := map[string]any{
		"state":            state,
		"replay_id":        "replay-1",
		"provider_subject": "subject-1",
		"audience":         "trisaura-issuer",
		"expires_at":       "2026-05-05T12:05:00Z",
		"assertion":        payload,
		"signature":        signProviderAssertion("provider-secret", payload),
	}

	first := call(h, http.MethodPost, "/api/v1/vc/tw/callback", body)
	if first.Code != http.StatusOK {
		t.Fatalf("first callback failed: %d %s", first.Code, first.Body)
	}
	replay := call(h, http.MethodPost, "/api/v1/vc/tw/callback", body)
	if replay.Code != http.StatusConflict {
		t.Fatalf("expected replay conflict, got %d %s", replay.Code, replay.Body)
	}
	if bodyJSON(t, replay)["error"] != "callback_replay" {
		t.Fatalf("unexpected replay error: %s", replay.Body)
	}
}
```

Add these tests in the same file:

```go
func TestTWProviderCallbackStateMismatchRejected(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)
	call(h, http.MethodPost, "/api/v1/vc/tw/start", map[string]any{
		"did": testDID, "email": testEmail,
	})

	payload := "wrong-state|subject-1|trisaura-issuer|2026-05-05T12:05:00Z"
	response := call(h, http.MethodPost, "/api/v1/vc/tw/callback", map[string]any{
		"state":            "wrong-state",
		"provider_subject": "subject-1",
		"audience":         "trisaura-issuer",
		"expires_at":       "2026-05-05T12:05:00Z",
		"assertion":        payload,
		"signature":        signProviderAssertion("provider-secret", payload),
	})
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "state_mismatch" {
		t.Fatalf("unexpected error: %s", response.Body)
	}
}

func TestTWProviderIssueBeforeCallbackRejected(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)
	start := call(h, http.MethodPost, "/api/v1/vc/tw/start", map[string]any{
		"did": testDID, "email": testEmail,
	})
	offerID := bodyJSON(t, start)["offer_id"].(string)

	response := call(h, http.MethodPost, "/api/v1/vc/tw/issue", map[string]any{
		"did": testDID, "email": testEmail, "offer_id": offerID,
	})
	if response.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "provider_not_verified" {
		t.Fatalf("unexpected error: %s", response.Body)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/api
```

Expected: FAIL because `ConfigureTWProvider`, `TWProviderConfig`, and the TW endpoints do not exist.

- [ ] **Step 3: Implement handler config and endpoints**

Modify `handler.go`:

```go
type TWProviderConfig struct {
	SessionStore provider.SessionStore
	Verifier     provider.ProofVerifier
	BaseAuthURL  string
	TTL          time.Duration
}
```

Add fields to `Handler`:

```go
twStore     provider.SessionStore
twVerifier  provider.ProofVerifier
twAuthURL   string
twTTL       time.Duration
now         func() time.Time
```

Add:

```go
func (h *Handler) ConfigureTWProvider(config TWProviderConfig) {
	h.twStore = config.SessionStore
	h.twVerifier = config.Verifier
	h.twAuthURL = config.BaseAuthURL
	h.twTTL = config.TTL
	if h.twTTL <= 0 {
		h.twTTL = 5 * time.Minute
	}
	if h.now == nil {
		h.now = time.Now
	}
}
```

Register:

```go
mux.HandleFunc("POST /api/v1/vc/tw/start", h.twStart)
mux.HandleFunc("POST /api/v1/vc/tw/callback", h.twCallback)
mux.HandleFunc("GET /api/v1/vc/tw/status/{offer_id}", h.twStatus)
mux.HandleFunc("POST /api/v1/vc/tw/issue", h.twIssue)
```

Endpoint behavior:

- `twStart` validates DID/email, creates random `offer_id` and `state`, stores `AuthSession`, and returns `offer_id`, `state`, `authorization_url`, `expires_at`.
- `twCallback` verifies proof, consumes state/replay ID, computes subject commitment with existing `commitment.Compute`, stores `VerifiedSession`, and returns `{"status":"verified","offer_id":"offer-1"}`.
- `twStatus` returns `pending`, `verified`, or `not_found`.
- `twIssue` validates DID/email/offer ID, consumes the verified session, checks DID/email match, issues the VC with the stored subject commitment, and returns a JSON object with the issued VC at the `vc` key.

Error mapping:

- replay: HTTP 409 `callback_replay`
- state not found or mismatch: HTTP 401 `state_mismatch`
- expired auth session: HTTP 401 `expired_session`
- missing proof: HTTP 422 `missing_provider_proof`
- invalid signature/audience/expiry: HTTP 401 `invalid_provider_proof`
- issue before verified callback: HTTP 409 `provider_not_verified`

- [ ] **Step 4: Run API tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/api
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ansible_issuer/go/internal/api/handler.go ansible_issuer/go/internal/api/tw_provider_flow_test.go
git commit -m "feat: add TW provider issuer flow"
```

## Task 4: Server Wiring And Environment

**Files:**

- Modify: `ansible_issuer/go/cmd/server/main.go`
- Test: `ansible_issuer/go/internal/api/tw_provider_flow_test.go`
- Create: `docs/architecture/tw_provider_production_integration.md`

- [ ] **Step 1: Add server wiring tests where practical**

Extend API tests to build a handler with file-backed store using:

```go
store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "sessions.json"), func() time.Time {
	return now
})
if err != nil {
	t.Fatalf("new file store: %v", err)
}
```

Expected behavior must match the in-memory store flow.

- [ ] **Step 2: Wire server config**

Modify `cmd/server/main.go` to read:

- `TW_PROVIDER_SESSION_STORE_PATH`
- `TW_PROVIDER_AUTH_URL`
- `TW_PROVIDER_SHARED_SECRET`
- `TW_PROVIDER_AUDIENCE`
- `TW_PROVIDER_SESSION_TTL_SECONDS`

When all provider config values are present, call `handler.ConfigureTWProvider`. When any required value is missing and `MOCK_MODE=false`, fail startup with a clear message:

```text
TW provider config missing: TW_PROVIDER_SESSION_STORE_PATH, TW_PROVIDER_AUTH_URL, TW_PROVIDER_SHARED_SECRET, TW_PROVIDER_AUDIENCE
```

When `MOCK_MODE=true`, wire a file store under `os.TempDir()` and a contract verifier with a dev-only shared secret so local app tests can exercise the flow.

- [ ] **Step 3: Write production integration doc**

Create `docs/architecture/tw_provider_production_integration.md` with:

- endpoint sequence diagram in text form;
- environment variables;
- provider callback field mapping;
- replay/session retention rule;
- no-log fields: `assertion`, `provider_subject`, raw national ID, legal name, certificate serial;
- deployment requirement: session store path must be on persistent encrypted storage for single-node deployments.

- [ ] **Step 4: Run issuer tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./...
```

Expected: PASS. Linker warnings about missing platform load command are acceptable on the current macOS Go toolchain when exit code is 0.

- [ ] **Step 5: Commit**

```bash
git add ansible_issuer/go/cmd/server/main.go ansible_issuer/go/internal/api/tw_provider_flow_test.go docs/architecture/tw_provider_production_integration.md
git commit -m "feat: wire TW provider server config"
```

## Task 5: Flutter Issuer Client Support

**Files:**

- Modify: `ansible_node/app/lib/services/vc_issuer_client.dart`
- Test: `ansible_node/app/test/vc_issuer_client_test.dart`

- [ ] **Step 1: Write failing client tests**

Add tests:

```dart
test('startTwProviderFlow posts did and email to /api/v1/vc/tw/start', () async {
  final client = VcIssuerClient(
    baseUrl: 'http://issuer.test',
    client: MockClient((request) async {
      expect(request.url.path, '/api/v1/vc/tw/start');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['did'], 'did:plc:abcdefghijklmnop');
      expect(body['email'], 'alice@example.com');
      return http.Response(
        jsonEncode({
          'offer_id': 'offer-1',
          'state': 'state-1',
          'authorization_url': 'https://provider.example/authorize?state=state-1',
          'expires_at': '2026-05-05T12:05:00Z',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  final offer = await client.startTwProviderFlow(
    did: 'did:plc:abcdefghijklmnop',
    email: 'alice@example.com',
  );

  expect(offer.offerId, 'offer-1');
  expect(offer.authorizationUrl.toString(), contains('state-1'));
});

test('issueTwProviderCredential posts offer id to /api/v1/vc/tw/issue', () async {
  final client = VcIssuerClient(
    baseUrl: 'http://issuer.test',
    client: MockClient((request) async {
      expect(request.url.path, '/api/v1/vc/tw/issue');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['offer_id'], 'offer-1');
      return http.Response(jsonEncode({'vc': {'id': 'vc-1'}}), 200);
    }),
  );

  final vc = await client.issueTwProviderCredential(
    did: 'did:plc:abcdefghijklmnop',
    email: 'alice@example.com',
    offerId: 'offer-1',
  );

  expect(vc['id'], 'vc-1');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd ansible_node/app
flutter test test/vc_issuer_client_test.dart
```

Expected: FAIL because client methods and model classes do not exist.

- [ ] **Step 3: Implement client models and methods**

Add:

```dart
class TwProviderOffer {
  final String offerId;
  final String state;
  final Uri authorizationUrl;
  final DateTime expiresAt;

  const TwProviderOffer({
    required this.offerId,
    required this.state,
    required this.authorizationUrl,
    required this.expiresAt,
  });

  factory TwProviderOffer.fromJson(Map<String, dynamic> json) =>
      TwProviderOffer(
        offerId: json['offer_id'] as String,
        state: json['state'] as String,
        authorizationUrl: Uri.parse(json['authorization_url'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class TwProviderStatus {
  final String status;

  const TwProviderStatus({required this.status});

  bool get isVerified => status == 'verified';
}
```

Add methods:

```dart
Future<TwProviderOffer> startTwProviderFlow({
  required String did,
  required String email,
}) async {
  final body = await _postJson('/api/v1/vc/tw/start', {
    'did': did,
    'email': email,
  });
  return TwProviderOffer.fromJson(body);
}

Future<TwProviderStatus> getTwProviderStatus(String offerId) async {
  final body = await _getJson('/api/v1/vc/tw/status/$offerId');
  return TwProviderStatus(status: body['status'] as String? ?? 'unknown');
}

Future<Map<String, dynamic>> issueTwProviderCredential({
  required String did,
  required String email,
  required String offerId,
}) async {
  final body = await _postJson('/api/v1/vc/tw/issue', {
    'did': did,
    'email': email,
    'offer_id': offerId,
  });
  return body['vc'] as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _getJson(String path) async {
  final response = await _client
      .get(
        _endpoint(path),
        headers: const {'content-type': 'application/json'},
      )
      .timeout(timeout);

  final decoded = _decodeObject(response.body);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw VcIssuerException(
      statusCode: response.statusCode,
      error: (decoded['error'] as String?) ?? 'unknown_error',
    );
  }
  return decoded;
}
```

Use existing `_postJson` and add `_getJson` for status.

- [ ] **Step 4: Run client tests**

Run:

```bash
cd ansible_node/app
flutter test test/vc_issuer_client_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ansible_node/app/lib/services/vc_issuer_client.dart ansible_node/app/test/vc_issuer_client_test.dart
git commit -m "feat: add TW provider issuer client methods"
```

## Task 6: Privacy Guardrails And External Sandbox Test

**Files:**

- Create: `ansible_issuer/go/internal/api/privacy_test.go`
- Create: `ansible_issuer/go/internal/provider/external_provider_test.go`
- Modify: `docs/architecture/tw_provider_production_integration.md`

- [ ] **Step 1: Write privacy regression tests**

Create `privacy_test.go`:

```go
package api_test

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestTWProviderErrorsDoNotEchoSensitiveCallbackFields(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)

	response := call(h, http.MethodPost, "/api/v1/vc/tw/callback", map[string]any{
		"state":            "wrong-state",
		"assertion":        "SIGNED_ASSERTION_PAYLOAD",
		"provider_subject": "A123456789",
		"legalName":        "Example Name",
		"certificateSerial": "CERT-123",
	})

	body := response.Body.String()
	for _, forbidden := range []string{"SIGNED_ASSERTION_PAYLOAD", "A123456789", "Example Name", "CERT-123"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("response leaked sensitive field %q: %s", forbidden, body)
		}
	}
}
```

- [ ] **Step 2: Write external sandbox test**

Create `external_provider_test.go`:

```go
package provider_test

import (
	"os"
	"testing"
)

func TestExternalTWProviderSandboxAvailable(t *testing.T) {
	endpoint := os.Getenv("TW_PROVIDER_SANDBOX_URL")
	clientID := os.Getenv("TW_PROVIDER_SANDBOX_CLIENT_ID")
	if endpoint == "" || clientID == "" {
		t.Skip("TW provider sandbox unavailable: missing TW_PROVIDER_SANDBOX_URL or TW_PROVIDER_SANDBOX_CLIENT_ID")
	}

	t.Fatalf("sandbox contract test must be implemented against the approved partner callback fixture before production enablement")
}
```

This test intentionally skips without credentials and intentionally fails when credentials exist until the approved partner fixture is wired. That prevents silently claiming production-provider coverage without a real sandbox.

- [ ] **Step 3: Run targeted tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 -ldflags=-linkmode=external ./internal/api ./internal/provider
```

Expected: PASS when sandbox env vars are absent, with skip message for `TestExternalTWProviderSandboxAvailable`.

- [ ] **Step 4: Document sandbox gate**

Add to `docs/architecture/tw_provider_production_integration.md`:

```markdown
## External Sandbox Gate

CI may run without partner credentials. In that case the external provider test
must skip with the missing environment variable names. When credentials are
present, the sandbox test must execute a partner-approved callback fixture and
must fail until that fixture is implemented.
```

- [ ] **Step 5: Commit**

```bash
git add ansible_issuer/go/internal/api/privacy_test.go ansible_issuer/go/internal/provider/external_provider_test.go docs/architecture/tw_provider_production_integration.md
git commit -m "test: add TW provider privacy and sandbox gates"
```

## Task 7: Full Verification And Merge Prep

**Files:**

- Modify: `README.md`
- Modify: `docs/architecture/tw_provider_production_integration.md`

- [ ] **Step 1: Add README status**

Add under the social graph section or component status:

```markdown
## TW Provider Issuance Direction

The issuer supports a production-shaped TW provider flow with single-use auth
state, replay rejection, provider proof verification boundaries, and holder-bound
credential issuance after callback verification. Raw provider assertions and
government identity fields stay inside the issuer boundary and must not be
logged or stored.
```

- [ ] **Step 2: Run full verification**

Run:

```bash
cd ansible_issuer/go && go test -count=1 -ldflags=-linkmode=external ./...
cd ansible_core/store && dart test
cd ansible_core/vc && flutter test
cd ansible_node/app && flutter test
```

Expected:

- Go issuer tests pass; macOS linker warnings are acceptable only with exit code 0.
- Store tests pass.
- VC package Flutter tests pass.
- App Flutter tests pass.

- [ ] **Step 3: Run privacy scan**

Run:

```bash
rg -n "nationalId|legalName|birthDate|certificateSerial|MOICA|TW FidO|provider_subject|assertion" ansible_issuer ansible_node/app ansible_core/vc
```

Expected:

- `provider_subject` and `assertion` may appear in provider boundary code, provider tests, and provider contract docs.
- Raw identity fields may appear in negative tests and docs only.
- No app UI or wallet storage code persists raw provider assertions or national identity fields.

- [ ] **Step 4: Clean generated artifacts**

Run:

```bash
git status --short
```

Restore generated `.dart_tool` changes and keep intentional lockfile changes only when they are required by a dependency graph change:

```bash
git restore ansible_core/store/.dart_tool ansible_core/vc/.dart_tool ansible_node/app/.dart_tool
```

- [ ] **Step 5: Commit final docs**

```bash
git add README.md docs/architecture/tw_provider_production_integration.md
git commit -m "docs: document TW provider production flow"
```

## Execution Notes

- Start this implementation from a new branch off `origin/main`: `codex/tw-provider-production-integration`.
- Preserve the existing OTP/mock endpoints until the app no longer depends on them.
- Do not log callback request bodies. Tests should assert response bodies do not echo sensitive callback fields.
- Use `go test -ldflags=-linkmode=external` on this macOS toolchain because plain `go test ./...` has shown `missing LC_UUID load command` aborts for some test binaries.
- Use `flutter test` for `ansible_core/vc`; `dart test` is not valid there because the package imports Flutter libraries.
