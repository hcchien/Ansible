package api_test

import (
	"bytes"
	"context"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/api"
	"github.com/trisaura/ansible_issuer/internal/provider"
)

type fakeMobileMoicaBroker struct {
	startRequest provider.MobileMoicaStartRequest
	verifyCalls  int
	pendingCount int
}

func (b *fakeMobileMoicaBroker) Start(_ context.Context, request provider.MobileMoicaStartRequest) (provider.MobileMoicaStartResult, error) {
	b.startRequest = request
	return provider.MobileMoicaStartResult{
		DeepLinkURL: "mobilemoica://moica.moi.gov.tw/a2a/verifySign?sp_ticket=contract-ticket&rtn_url=encoded&rtn_val=",
		TicketID:    "contract-ticket",
		ExpiresAt:   request.ExpiresAt,
	}, nil
}

func (b *fakeMobileMoicaBroker) Verify(_ context.Context, offerID, state string) (provider.MobileMoicaVerificationResult, error) {
	b.verifyCalls += 1
	if b.verifyCalls <= b.pendingCount {
		return provider.MobileMoicaVerificationResult{}, provider.ErrMobileMoicaResultPending
	}
	return provider.MobileMoicaVerificationResult{
		ProviderSubject:  "provider-subject-redacted",
		ReplayID:         "replay-" + offerID,
		AssuranceContext: "mobilemoica_rp_explicit_disclosure",
		ExpiresAt:        b.startRequest.ExpiresAt,
	}, nil
}

func configureMobileMoica(t *testing.T, h *api.Handler, now time.Time, broker provider.MobileMoicaRPBroker) {
	t.Helper()
	h.ConfigureMobileMoicaRP(api.MobileMoicaRPConfig{
		Enabled:   true,
		Store:     provider.NewMemorySessionStore(time.Now),
		Broker:    broker,
		ReturnURL: "trisaura://mobilemoica/callback",
		TTL:       5 * time.Minute,
		Approval: provider.MobileMoicaApprovalConfig{
			LegalApprovalID:        "legal-review",
			PrivacyApprovalID:      "privacy-review",
			SecurityApprovalID:     "security-review",
			ConstitutionApprovalID: "constitution-exception",
		},
	})
}

func TestMobileMoicaRPStartUnconfigured(t *testing.T) {
	h := newTestHandler(t)

	response := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{})

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "mobilemoica_rp_unconfigured" {
		t.Fatalf("unexpected error: %s", response.Body)
	}
}

func TestMobileMoicaRPStartRequiresApprovalGate(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	h := newTestHandler(t)
	h.ConfigureMobileMoicaRP(api.MobileMoicaRPConfig{
		Enabled: true,
		Store:   provider.NewMemorySessionStore(func() time.Time { return now }),
		Broker:  &fakeMobileMoicaBroker{},
		TTL:     5 * time.Minute,
	})

	response := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{})

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "mobilemoica_rp_unconfigured" {
		t.Fatalf("unexpected error: %s", response.Body)
	}
}

func TestMobileMoicaRPStartRejectsInvalidInput(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, &fakeMobileMoicaBroker{})

	tests := []struct {
		name string
		body map[string]any
		want string
	}{
		{
			name: "invalid did",
			body: map[string]any{
				"holder_did":        "did:key:z6Mk",
				"national_id":       "Z123000000",
				"consent_version":   "mobilemoica-rp-v1",
				"consent_copy_hash": "sha256:copy-hash",
			},
			want: "invalid_did",
		},
		{
			name: "invalid national id",
			body: map[string]any{
				"holder_did":        testDID,
				"national_id":       "not-a-national-id",
				"consent_version":   "mobilemoica-rp-v1",
				"consent_copy_hash": "sha256:copy-hash",
			},
			want: "invalid_national_id",
		},
		{
			name: "missing consent",
			body: map[string]any{
				"holder_did":  testDID,
				"national_id": "Z123000000",
			},
			want: "missing_field",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			response := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", tc.body)
			if response.Code != http.StatusUnprocessableEntity {
				t.Fatalf("expected 422, got %d %s", response.Code, response.Body)
			}
			if bodyJSON(t, response)["error"] != tc.want {
				t.Fatalf("unexpected error: %s", response.Body)
			}
		})
	}
}

func TestMobileMoicaRPStartReturnsDeepLinkWithoutLeakingNationalID(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	broker := &fakeMobileMoicaBroker{}
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, broker)

	response := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{
		"holder_did":        testDID,
		"national_id":       "Z123000000",
		"consent_version":   "mobilemoica-rp-v1",
		"consent_copy_hash": "sha256:copy-hash",
		"locale":            "zh-Hant-TW",
	})

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", response.Code, response.Body)
	}
	body := bodyJSON(t, response)
	if !strings.HasPrefix(body["deep_link_url"].(string), "mobilemoica://") {
		t.Fatalf("expected mobilemoica deep link, got %v", body)
	}
	if strings.Contains(response.Body.String(), "Z123000000") {
		t.Fatalf("response leaked national ID: %s", response.Body)
	}
	if broker.startRequest.NationalID != "Z123000000" {
		t.Fatalf("broker did not receive national ID for ticket request")
	}
}

func TestMobileMoicaRPStatusThenIssueCredential(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	broker := &fakeMobileMoicaBroker{pendingCount: 1}
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, broker)

	start := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{
		"holder_did":        testDID,
		"national_id":       "Z123000000",
		"consent_version":   "mobilemoica-rp-v1",
		"consent_copy_hash": "sha256:copy-hash",
	})
	offerID := bodyJSON(t, start)["offer_id"].(string)

	pending := call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/"+offerID, nil)
	if bodyJSON(t, pending)["status"] != "pending" {
		t.Fatalf("expected pending, got %s", pending.Body)
	}

	verified := call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/"+offerID, nil)
	if bodyJSON(t, verified)["status"] != "verified" {
		t.Fatalf("expected verified, got %s", verified.Body)
	}

	issue := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/issue", map[string]any{
		"holder_did": testDID,
		"offer_id":   offerID,
	})
	if issue.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", issue.Code, issue.Body)
	}
	body := bodyJSON(t, issue)
	vcMap := body["vc"].(map[string]any)
	claims := vcMap["credentialSubject"].(map[string]any)
	if claims["assuranceMethod"] != "mobilemoica_rp_explicit_disclosure" {
		t.Fatalf("unexpected VC claims: %v", claims)
	}
	for _, leaked := range []string{
		"Z123000000",
		"provider-subject-redacted",
		"signed_response",
		"legalName",
		"certificateSerialNumber",
		"rawProviderAssertion",
	} {
		if strings.Contains(issue.Body.String(), leaked) {
			t.Fatalf("issue response leaked %q: %s", leaked, issue.Body)
		}
	}
}

func TestMobileMoicaRPLogsFlowWithoutSensitiveValues(t *testing.T) {
	var logs bytes.Buffer
	previousWriter := log.Writer()
	previousFlags := log.Flags()
	log.SetOutput(&logs)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(previousWriter)
		log.SetFlags(previousFlags)
	})

	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	broker := &fakeMobileMoicaBroker{pendingCount: 1}
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, broker)

	start := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{
		"holder_did":        testDID,
		"national_id":       "Z123000000",
		"consent_version":   "mobilemoica-rp-v1",
		"consent_copy_hash": "sha256:copy-hash",
	})
	offerID := bodyJSON(t, start)["offer_id"].(string)

	call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/"+offerID, nil)
	call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/"+offerID, nil)
	call(h, http.MethodPost, "/api/v1/vc/mobilemoica/issue", map[string]any{
		"holder_did": testDID,
		"offer_id":   offerID,
	})

	output := logs.String()
	for _, want := range []string{
		"event=mobilemoica_rp_start status=created offer_ref=",
		"event=mobilemoica_rp_status status=pending offer_ref=",
		"event=mobilemoica_rp_status status=verified offer_ref=",
		"event=mobilemoica_rp_issue status=issued offer_ref=",
	} {
		if !strings.Contains(output, want) {
			t.Fatalf("missing log %q in:\n%s", want, output)
		}
	}
	for _, leaked := range []string{
		offerID,
		"Z123000000",
		"provider-subject-redacted",
		testDID,
		"mobilemoica://",
		"contract-ticket",
		"signed_response",
	} {
		if strings.Contains(output, leaked) {
			t.Fatalf("log leaked %q:\n%s", leaked, output)
		}
	}
}

func TestMobileMoicaRPIssueRejectsDuplicateBinding(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, &fakeMobileMoicaBroker{})

	issueCredential := func(holderDID string) *httptest.ResponseRecorder {
		start := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{
			"holder_did":        holderDID,
			"national_id":       "Z123000000",
			"consent_version":   "mobilemoica-rp-v1",
			"consent_copy_hash": "sha256:copy-hash",
		})
		offerID := bodyJSON(t, start)["offer_id"].(string)
		status := call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/"+offerID, nil)
		if bodyJSON(t, status)["status"] != "verified" {
			t.Fatalf("expected verified, got %s", status.Body)
		}
		return call(h, http.MethodPost, "/api/v1/vc/mobilemoica/issue", map[string]any{
			"holder_did": holderDID,
			"offer_id":   offerID,
		})
	}

	first := issueCredential(testDID)
	if first.Code != http.StatusOK {
		t.Fatalf("expected first issue 200, got %d %s", first.Code, first.Body)
	}
	second := issueCredential("did:plc:zzzzzzzzzzzzzzzz")
	if second.Code != http.StatusConflict {
		t.Fatalf("expected duplicate conflict, got %d %s", second.Code, second.Body)
	}
	if bodyJSON(t, second)["error"] != "duplicate_active_credential" {
		t.Fatalf("unexpected duplicate error: %s", second.Body)
	}
}
