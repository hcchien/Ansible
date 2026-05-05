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
