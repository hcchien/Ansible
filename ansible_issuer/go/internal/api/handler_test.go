package api_test

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/api"
	"github.com/trisaura/ansible_issuer/internal/otp"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

const (
	testDID    = "did:plc:abcdefghijklmnop"
	testEmail  = "alice@example.com"
	testPepper = "test-pepper"
)

func newTestHandler(t *testing.T) *api.Handler {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	iss, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.trisaura.io",
		IssuerURL:  "https://issuer.trisaura.io",
		PrivKeyHex: hex.EncodeToString(priv.Seed()),
		TTLDays:    90,
	}, vc.NewStore())
	if err != nil {
		t.Fatal(err)
	}
	return api.NewHandler(
		otp.NewStore(5*time.Minute),
		provider.Mock{},
		iss,
		testPepper,
		true,
	)
}

func call(h *api.Handler, method, path string, body any) *httptest.ResponseRecorder {
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	r := httptest.NewRequest(method, path, &buf)
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux := http.NewServeMux()
	h.Register(mux)
	mux.ServeHTTP(w, r)
	return w
}

func bodyJSON(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode body: %v\nbody: %s", err, w.Body)
	}
	return out
}

func getOTP(t *testing.T, h *api.Handler) string {
	t.Helper()
	w := call(h, http.MethodPost, "/api/v1/vc/request", map[string]any{
		"did": testDID, "email": testEmail,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("request failed: %d %s", w.Code, w.Body)
	}
	code, ok := bodyJSON(t, w)["otp"].(string)
	if !ok {
		t.Fatal("no otp in request response")
	}
	return code
}

func TestHealthzReturnsOK(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodGet, "/healthz", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
	}
	if bodyJSON(t, w)["status"] != "ok" {
		t.Fatalf("unexpected body: %v", bodyJSON(t, w))
	}
}

func TestReadyzReportsUnconfiguredTWProvider(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodGet, "/readyz", nil)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d: %s", w.Code, w.Body)
	}
	body := bodyJSON(t, w)
	if body["tw_provider"] != "unconfigured" {
		t.Fatalf("unexpected body: %v", body)
	}
}

func TestReadyzReportsConfiguredTWProvider(t *testing.T) {
	h := newTestHandler(t)
	h.ConfigureTWProvider(api.TWProviderConfig{
		SessionStore: provider.NewMemorySessionStore(time.Now),
		Verifier: provider.NewContractProofVerifier(provider.ContractProofConfig{
			SharedSecret: "provider-secret",
			Audience:     "trisaura-issuer",
			Now:          time.Now,
		}),
		BaseAuthURL: "https://provider.example/authorize",
		TTL:         5 * time.Minute,
	})

	w := call(h, http.MethodGet, "/readyz", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
	}
	body := bodyJSON(t, w)
	if body["tw_provider"] != "configured" {
		t.Fatalf("unexpected body: %v", body)
	}
	if body["authorization_url"] != nil || body["session_store_path"] != nil {
		t.Fatalf("readiness leaked config details: %v", body)
	}
}

func TestRequest_MockModeReturnsOTP(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodPost, "/api/v1/vc/request", map[string]any{
		"did": testDID, "email": testEmail,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
	}
	code, ok := bodyJSON(t, w)["otp"].(string)
	if !ok || len(code) != 6 {
		t.Fatalf("expected 6-digit OTP, got %v", bodyJSON(t, w))
	}
}

func TestRequest_MissingEmail(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodPost, "/api/v1/vc/request", map[string]any{"did": testDID})
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d", w.Code)
	}
}

func TestRequest_InvalidEmail(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodPost, "/api/v1/vc/request", map[string]any{
		"did": testDID, "email": "not-an-email",
	})
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d", w.Code)
	}
	if bodyJSON(t, w)["error"] != "invalid_email" {
		t.Fatalf("unexpected error: %v", bodyJSON(t, w))
	}
}

func TestRequest_InvalidDID(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodPost, "/api/v1/vc/request", map[string]any{
		"did": "did:key:z6Mk", "email": testEmail,
	})
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d", w.Code)
	}
	if bodyJSON(t, w)["error"] != "invalid_did" {
		t.Fatalf("unexpected error: %v", bodyJSON(t, w))
	}
}

func TestIssue_ReturnsSignedHumanityCredential(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodPost, "/api/v1/vc/issue", map[string]any{
		"did": testDID, "email": testEmail, "otp": getOTP(t, h),
	})
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
	}
	vcMap, ok := bodyJSON(t, w)["vc"].(map[string]any)
	if !ok {
		t.Fatalf("expected vc key, got %v", bodyJSON(t, w))
	}
	types, _ := vcMap["type"].([]any)
	found := false
	for _, v := range types {
		if v == "TrisAuraHumanityCredential" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected TrisAuraHumanityCredential type, got %v", types)
	}
	if vcMap["proof"] == nil {
		t.Fatal("expected proof in issued credential")
	}
}

func TestIssue_OTPSingleUse(t *testing.T) {
	h := newTestHandler(t)
	code := getOTP(t, h)

	issue := map[string]any{"did": testDID, "email": testEmail, "otp": code}
	first := call(h, http.MethodPost, "/api/v1/vc/issue", issue)
	if first.Code != http.StatusOK {
		t.Fatalf("first issue failed: %d %s", first.Code, first.Body)
	}
	second := call(h, http.MethodPost, "/api/v1/vc/issue", issue)
	if second.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 on reuse, got %d", second.Code)
	}
	if bodyJSON(t, second)["error"] != "invalid_otp" {
		t.Fatalf("expected invalid_otp, got %v", bodyJSON(t, second))
	}
}

func TestIssue_WrongOTP(t *testing.T) {
	h := newTestHandler(t)
	getOTP(t, h) // issue but discard
	w := call(h, http.MethodPost, "/api/v1/vc/issue", map[string]any{
		"did": testDID, "email": testEmail, "otp": "000000",
	})
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestIssue_DuplicateActiveCredential(t *testing.T) {
	h := newTestHandler(t)

	first := call(h, http.MethodPost, "/api/v1/vc/issue", map[string]any{
		"did": testDID, "email": testEmail, "otp": getOTP(t, h),
	})
	if first.Code != http.StatusOK {
		t.Fatalf("first issue failed: %d %s", first.Code, first.Body)
	}

	second := call(h, http.MethodPost, "/api/v1/vc/issue", map[string]any{
		"did": testDID, "email": testEmail, "otp": getOTP(t, h),
	})
	if second.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", second.Code, second.Body)
	}
	if bodyJSON(t, second)["error"] != "duplicate_active_credential" {
		t.Fatalf("expected duplicate_active_credential, got %v", bodyJSON(t, second))
	}
}
