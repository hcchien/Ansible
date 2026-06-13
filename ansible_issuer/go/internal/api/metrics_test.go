package api_test

import (
	"net/http"
	"strings"
	"testing"
)

// GET /metrics returns Prometheus text and the declared series are present even
// before any traffic.
func TestMetricsEndpointExposesDeclaredSeries(t *testing.T) {
	h := newTestHandler(t)

	w := call(h, http.MethodGet, "/metrics", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("metrics status: %d", w.Code)
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Fatalf("unexpected content-type: %s", ct)
	}

	body := w.Body.String()
	for _, want := range []string{
		"# TYPE issuer_requests_total counter",
		"# TYPE issuer_credentials_issued_total counter",
		"# TYPE issuer_errors_total counter",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("metrics output missing %q\n%s", want, body)
		}
	}
}

// Exercising an instrumented path (issue an email credential) increments the
// request and credential counters.
func TestMetricsCountsRequestsAndIssuance(t *testing.T) {
	h := newTestHandler(t)

	otpCode := getOTP(t, h)
	w := call(h, http.MethodPost, "/api/v1/vc/issue", map[string]any{
		"did": testDID, "email": testEmail, "otp": otpCode,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("issue failed: %d %s", w.Code, w.Body)
	}

	metrics := call(h, http.MethodGet, "/metrics", nil).Body.String()
	for _, want := range []string{
		`issuer_requests_total{endpoint="vc_issue"} 1`,
		`issuer_credentials_issued_total{type="email"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics output missing %q\n%s", want, metrics)
		}
	}
}
