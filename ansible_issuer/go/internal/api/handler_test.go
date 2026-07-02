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
	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/otp"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

const (
	testDID    = "did:plc:abcdefghijklmnop"
	testEmail  = "alice@example.com"
	testPepper = "test-pepper"
)

type fakePassportVerifier struct {
	err error
}

func (v fakePassportVerifier) VerifyPassportBinding(
	proof api.PassportBindingProof,
) (api.PassportBindingResult, error) {
	if v.err != nil {
		return api.PassportBindingResult{}, v.err
	}
	return api.PassportBindingResult{
		NationalIDHash:     proof.NationalIDHash,
		PassportNumberHash: proof.PassportNumberHash,
		Nationality:        proof.Nationality,
		VerifiedAt:         time.Date(2026, 5, 24, 0, 0, 0, 0, time.UTC),
	}, nil
}

func configurePassportVerifier(h *api.Handler) {
	h.ConfigurePassport(api.PassportConfig{Verifier: fakePassportVerifier{}})
}

func newTestHandler(t *testing.T) *api.Handler {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	iss, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.elix.cool",
		IssuerURL:  "https://issuer.elix.cool",
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
		commitment.NewSet(testPepper, nil),
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

func TestIssue_ReturnsSignedEmailCredential(t *testing.T) {
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
	foundEmail := false
	for _, v := range types {
		if v == "EmailCredential" {
			foundEmail = true
		}
		if v == "TrisAuraHumanityCredential" {
			t.Fatalf("Email OTP must not issue TrisAuraHumanityCredential, got %v", types)
		}
	}
	if !foundEmail {
		t.Fatalf("expected EmailCredential type, got %v", types)
	}
	cs, _ := vcMap["credentialSubject"].(map[string]any)
	if cs["humanVerified"] == true {
		t.Fatalf("Email OTP must not set humanVerified=true, got %v", cs)
	}
	if cs["assuranceMethod"] != "email_otp" {
		t.Fatalf("expected email_otp assurance method, got %v", cs)
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

func TestIssue_EmailCredentialCanBeReissued(t *testing.T) {
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
	if second.Code != http.StatusOK {
		t.Fatalf("expected second contact credential 200, got %d: %s", second.Code, second.Body)
	}
	vcMap, ok := bodyJSON(t, second)["vc"].(map[string]any)
	if !ok {
		t.Fatalf("expected vc key, got %v", bodyJSON(t, second))
	}
	types, _ := vcMap["type"].([]any)
	for _, typ := range types {
		if typ == "TrisAuraHumanityCredential" {
			t.Fatalf("Email OTP must not issue TrisAuraHumanityCredential, got %v", types)
		}
	}
}

func TestPassportIssue_ReturnsPassportCredentialWithoutPassportIdentifiers(t *testing.T) {
	h := newTestHandler(t)
	configurePassportVerifier(h)
	w := call(h, http.MethodPost, "/api/v1/vc/passport/issue", map[string]any{
		"did":                   testDID,
		"nationality":           "TWN",
		"national_id_hash":      "national-id-hash-abc123",
		"passport_number_hash":  "passport-number-hash-abc123",
		"zkp_proof":             "proof-abc123",
		"zkp_circuit_version":   "passport_v1_dev",
		"verification_key_hash": "sha256:dev-passport-v1-placeholder",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
	}
	vcMap, ok := bodyJSON(t, w)["vc"].(map[string]any)
	if !ok {
		t.Fatalf("expected vc key, got %v", bodyJSON(t, w))
	}
	cs, _ := vcMap["credentialSubject"].(map[string]any)
	if cs["nationality"] != "TWN" {
		t.Fatalf("expected nationality claim, got %v", cs)
	}
	if cs["assuranceMethod"] != "passport_nfc" {
		t.Fatalf("expected passport_nfc method, got %v", cs)
	}
	for _, prohibited := range []string{"documentNumber", "passportNumber", "passportLocalUniqueId", "passportUid", "passport_uid", "nationalIdHash", "national_id_hash", "passportNumberHash", "passport_number_hash"} {
		if _, ok := cs[prohibited]; ok {
			t.Fatalf("credentialSubject must not contain %q", prohibited)
		}
	}
}

func TestPassportIssue_RejectsWhenVerifierIsUnconfigured(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodPost, "/api/v1/vc/passport/issue", map[string]any{
		"did":                   testDID,
		"nationality":           "TWN",
		"national_id_hash":      "national-id-hash-abc123",
		"passport_number_hash":  "passport-number-hash-abc123",
		"zkp_proof":             "proof-abc123",
		"zkp_circuit_version":   "passport_v1_dev",
		"verification_key_hash": "sha256:dev-passport-v1-placeholder",
	})
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d: %s", w.Code, w.Body)
	}
	if bodyJSON(t, w)["error"] != "passport_verifier_unconfigured" {
		t.Fatalf("unexpected error: %v", bodyJSON(t, w))
	}
}

func TestPassportIssue_RejectsDuplicatePassportBinding(t *testing.T) {
	h := newTestHandler(t)
	configurePassportVerifier(h)
	body := map[string]any{
		"did":                   testDID,
		"nationality":           "TWN",
		"national_id_hash":      "national-id-hash-abc123",
		"passport_number_hash":  "passport-number-hash-abc123",
		"zkp_proof":             "proof-abc123",
		"zkp_circuit_version":   "passport_v1_dev",
		"verification_key_hash": "sha256:dev-passport-v1-placeholder",
	}

	first := call(h, http.MethodPost, "/api/v1/vc/passport/issue", body)
	if first.Code != http.StatusOK {
		t.Fatalf("first issue failed: %d %s", first.Code, first.Body)
	}

	second := call(h, http.MethodPost, "/api/v1/vc/passport/issue", body)
	if second.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", second.Code, second.Body)
	}
	if bodyJSON(t, second)["error"] != "personhood_already_bound" {
		t.Fatalf("unexpected error: %v", bodyJSON(t, second))
	}
}

func TestPassportIssue_RejectsNationalIDAlreadyBoundByTWProvider(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)
	configurePassportVerifier(h)
	start := call(h, http.MethodPost, "/api/v1/vc/tw/start", map[string]any{
		"did": testDID, "email": testEmail,
	})
	if start.Code != http.StatusOK {
		t.Fatalf("tw start failed: %d %s", start.Code, start.Body)
	}
	startBody := bodyJSON(t, start)
	offerID := startBody["offer_id"].(string)
	state := startBody["state"].(string)
	callback := call(h, http.MethodPost, "/api/v1/vc/tw/callback", contractCallbackBody("provider-secret", "trisaura-issuer", provider.ProviderAssertion{
		State:           state,
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(5 * time.Minute),
	}))
	if callback.Code != http.StatusOK {
		t.Fatalf("tw callback failed: %d %s", callback.Code, callback.Body)
	}
	if first := call(h, http.MethodPost, "/api/v1/vc/tw/issue", map[string]any{
		"did": testDID, "email": testEmail, "offer_id": offerID,
	}); first.Code != http.StatusOK {
		t.Fatalf("tw issue failed: %d %s", first.Code, first.Body)
	}

	body := map[string]any{
		"did":         "did:plc:bcdefghijklmnopq",
		"nationality": "TWN",
		"national_id_hash": commitment.Compute(
			testPepper,
			"subject-1",
			"tw_natural_person_certificate",
		),
		"passport_number_hash":  "passport-number-hash-abc123",
		"zkp_proof":             "proof-abc123",
		"zkp_circuit_version":   "passport_v1_dev",
		"verification_key_hash": "sha256:dev-passport-v1-placeholder",
	}

	response := call(h, http.MethodPost, "/api/v1/vc/passport/issue", body)
	if response.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "personhood_already_bound" {
		t.Fatalf("unexpected error: %v", bodyJSON(t, response))
	}
}
