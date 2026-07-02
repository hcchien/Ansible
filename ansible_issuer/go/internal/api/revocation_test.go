package api_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/trisaura/ansible_issuer/internal/api"
)

// callWithAuth issues an HTTP call with an Authorization: Bearer <token> header.
func callWithAuth(h *api.Handler, method, path, token string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, nil)
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	mux := http.NewServeMux()
	h.Register(mux)
	mux.ServeHTTP(w, r)
	return w
}

func TestVCStatus_ReturnsActiveForIssuedCredential(t *testing.T) {
	h := newTestHandler(t)
	suffix := issueAndExtractSuffix(t, h)

	status := call(h, http.MethodGet, "/api/v1/vc/status/"+suffix, nil)
	if status.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", status.Code, status.Body)
	}
	body := bodyJSON(t, status)
	if body["status"] != "active" {
		t.Fatalf("expected active status, got %v", body)
	}
	if body["revoked"] != false {
		t.Fatalf("expected revoked=false, got %v", body)
	}
}

func TestVCStatus_UnknownCredentialReturns404(t *testing.T) {
	h := newTestHandler(t)
	status := call(h, http.MethodGet, "/api/v1/vc/status/deadbeefdeadbeef", nil)
	if status.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unknown credential, got %d %s", status.Code, status.Body)
	}
}

func TestVCRevoke_DisabledWithoutAdminToken(t *testing.T) {
	h := newTestHandler(t)
	suffix := issueAndExtractSuffix(t, h)

	// No ConfigureAdmin call: revocation must fail closed.
	resp := callWithAuth(h, http.MethodPost, "/api/v1/internal/vc/revoke/"+suffix, "anything")
	if resp.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when revocation unconfigured, got %d %s", resp.Code, resp.Body)
	}
}

func TestVCRevoke_RequiresValidBearerToken(t *testing.T) {
	h := newTestHandler(t)
	h.ConfigureAdmin("s3cret-admin-token")
	suffix := issueAndExtractSuffix(t, h)

	// Wrong token → 401.
	bad := callWithAuth(h, http.MethodPost, "/api/v1/internal/vc/revoke/"+suffix, "wrong-token")
	if bad.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for wrong token, got %d %s", bad.Code, bad.Body)
	}

	// Missing header → 401.
	none := call(h, http.MethodPost, "/api/v1/internal/vc/revoke/"+suffix, nil)
	if none.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 without token, got %d %s", none.Code, none.Body)
	}
}

func TestVCRevoke_RevokesAndStatusReflectsIt(t *testing.T) {
	h := newTestHandler(t)
	h.ConfigureAdmin("s3cret-admin-token")
	suffix := issueAndExtractSuffix(t, h)

	revoke := callWithAuth(h, http.MethodPost, "/api/v1/internal/vc/revoke/"+suffix, "s3cret-admin-token")
	if revoke.Code != http.StatusOK {
		t.Fatalf("expected 200 on revoke, got %d %s", revoke.Code, revoke.Body)
	}
	if bodyJSON(t, revoke)["status"] != "revoked" {
		t.Fatalf("unexpected revoke body: %s", revoke.Body)
	}

	status := call(h, http.MethodGet, "/api/v1/vc/status/"+suffix, nil)
	body := bodyJSON(t, status)
	if body["status"] != "revoked" || body["revoked"] != true {
		t.Fatalf("status endpoint did not reflect revocation: %v", body)
	}
}

func TestVCRevoke_UnknownCredentialReturns404(t *testing.T) {
	h := newTestHandler(t)
	h.ConfigureAdmin("s3cret-admin-token")
	resp := callWithAuth(h, http.MethodPost, "/api/v1/internal/vc/revoke/deadbeefdeadbeef", "s3cret-admin-token")
	if resp.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unknown credential, got %d %s", resp.Code, resp.Body)
	}
}

func TestIssuedCredentialCarriesCredentialStatus(t *testing.T) {
	h := newTestHandler(t)
	vcMap := issueEmailVC(t, h)
	cs, ok := vcMap["credentialStatus"].(map[string]any)
	if !ok {
		t.Fatalf("issued credential missing credentialStatus: %v", vcMap)
	}
	if _, ok := cs["id"].(string); !ok {
		t.Fatalf("credentialStatus missing id: %v", cs)
	}
	if !strings.Contains(cs["id"].(string), "/api/v1/vc/status/") {
		t.Fatalf("credentialStatus id is not a status URL: %v", cs["id"])
	}
}

// --- helpers ---

// issueEmailVC issues an email credential and returns the decoded vc map.
func issueEmailVC(t *testing.T, h *api.Handler) map[string]any {
	t.Helper()
	code := getOTP(t, h)
	resp := call(h, http.MethodPost, "/api/v1/vc/issue", map[string]any{
		"did": testDID, "email": testEmail, "otp": code,
	})
	if resp.Code != http.StatusOK {
		t.Fatalf("issue failed: %d %s", resp.Code, resp.Body)
	}
	vcMap, ok := bodyJSON(t, resp)["vc"].(map[string]any)
	if !ok {
		t.Fatalf("no vc in issue response: %s", resp.Body)
	}
	return vcMap
}

// issueAndExtractSuffix issues an email credential and returns the hex suffix of
// its credential id (the last path segment), used to key status/revoke.
func issueAndExtractSuffix(t *testing.T, h *api.Handler) string {
	t.Helper()
	vcMap := issueEmailVC(t, h)
	id, ok := vcMap["id"].(string)
	if !ok {
		t.Fatalf("credential missing id: %v", vcMap)
	}
	parts := strings.Split(id, "/")
	return parts[len(parts)-1]
}
