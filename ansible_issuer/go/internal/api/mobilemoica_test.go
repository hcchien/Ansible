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
	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
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

	// start returns the raw start response so callers can assert the duplicate
	// check (which runs at start, where the raw national ID is still available
	// for the pepper-rotation dual-check).
	start := func(holderDID string) *httptest.ResponseRecorder {
		return call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{
			"holder_did":        holderDID,
			"national_id":       "Z123000000",
			"consent_version":   "mobilemoica-rp-v1",
			"consent_copy_hash": "sha256:copy-hash",
		})
	}
	issueCredential := func(holderDID string, startResp *httptest.ResponseRecorder) *httptest.ResponseRecorder {
		offerID := bodyJSON(t, startResp)["offer_id"].(string)
		status := call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/"+offerID, nil)
		if bodyJSON(t, status)["status"] != "verified" {
			t.Fatalf("expected verified, got %s", status.Body)
		}
		return call(h, http.MethodPost, "/api/v1/vc/mobilemoica/issue", map[string]any{
			"holder_did": holderDID,
			"offer_id":   offerID,
		})
	}

	firstStart := start(testDID)
	if firstStart.Code != http.StatusOK {
		t.Fatalf("expected first start 200, got %d %s", firstStart.Code, firstStart.Body)
	}
	first := issueCredential(testDID, firstStart)
	if first.Code != http.StatusOK {
		t.Fatalf("expected first issue 200, got %d %s", first.Code, first.Body)
	}

	// The same person (national ID) starting again must be rejected at start.
	second := start("did:plc:zzzzzzzzzzzzzzzz")
	if second.Code != http.StatusConflict {
		t.Fatalf("expected duplicate conflict at start, got %d %s", second.Code, second.Body)
	}
	if bodyJSON(t, second)["error"] != "duplicate_active_credential" {
		t.Fatalf("unexpected duplicate error: %s", second.Body)
	}
}

func TestMobileMoicaRPStatusFailsClosedWithoutUnifiedBinding(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	store := provider.NewMemorySessionStore(func() time.Time { return now })
	h := newTestHandler(t)
	h.ConfigureMobileMoicaRP(api.MobileMoicaRPConfig{
		Enabled:   true,
		Store:     store,
		Broker:    &fakeMobileMoicaBroker{},
		ReturnURL: "trisaura://mobilemoica/callback",
		TTL:       5 * time.Minute,
		Approval: provider.MobileMoicaApprovalConfig{
			LegalApprovalID:        "legal-review",
			PrivacyApprovalID:      "privacy-review",
			SecurityApprovalID:     "security-review",
			ConstitutionApprovalID: "constitution-exception",
		},
	})
	if err := store.CreateAuthSession(provider.AuthSession{
		OfferID:   "legacy-offer",
		DID:       testDID,
		State:     "legacy-state",
		ExpiresAt: now.Add(5 * time.Minute),
	}); err != nil {
		t.Fatalf("create legacy auth session: %v", err)
	}

	response := call(h, http.MethodGet, "/api/v1/vc/mobilemoica/status/legacy-offer", nil)
	if response.Code != http.StatusInternalServerError {
		t.Fatalf("expected fail-closed 500, got %d %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "provider_session_error" {
		t.Fatalf("unexpected error: %s", response.Body)
	}
}

func TestMobileMoicaRPIssueBlocksPassportWithSameTWNationalIDBinding(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, &fakeMobileMoicaBroker{})
	configurePassportVerifier(h)

	mobileMoicaIssue := issueMobileMoicaForNationalID(t, h, testDID, "Z123000000")
	if mobileMoicaIssue.Code != http.StatusOK {
		t.Fatalf("expected MobileMoica issue 200, got %d %s", mobileMoicaIssue.Code, mobileMoicaIssue.Body)
	}

	passport := call(h, http.MethodPost, "/api/v1/vc/passport/issue", map[string]any{
		"did":         "did:plc:zzzzzzzzzzzzzzzz",
		"nationality": "TWN",
		"national_id_hash": commitment.Compute(
			testPepper,
			"Z123000000",
			vc.PersonhoodBindingTWNationalIDContext,
		),
		"passport_number_hash":  "passport-number-hash-abc123",
		"zkp_proof":             "proof-abc123",
		"zkp_circuit_version":   "passport_v1_dev",
		"verification_key_hash": "sha256:dev-passport-v1-placeholder",
	})
	if passport.Code != http.StatusConflict {
		t.Fatalf("expected passport duplicate conflict, got %d %s", passport.Code, passport.Body)
	}
	if bodyJSON(t, passport)["error"] != "personhood_already_bound" {
		t.Fatalf("unexpected duplicate error: %s", passport.Body)
	}
}

func TestMobileMoicaRPIssueRejectsPassportBoundTWNationalID(t *testing.T) {
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	h := newTestHandler(t)
	configureMobileMoica(t, h, now, &fakeMobileMoicaBroker{})
	configurePassportVerifier(h)

	passport := call(h, http.MethodPost, "/api/v1/vc/passport/issue", map[string]any{
		"did":         testDID,
		"nationality": "TWN",
		"national_id_hash": commitment.Compute(
			testPepper,
			"Z123000000",
			vc.PersonhoodBindingTWNationalIDContext,
		),
		"passport_number_hash":  "passport-number-hash-abc123",
		"zkp_proof":             "proof-abc123",
		"zkp_circuit_version":   "passport_v1_dev",
		"verification_key_hash": "sha256:dev-passport-v1-placeholder",
	})
	if passport.Code != http.StatusOK {
		t.Fatalf("expected passport issue 200, got %d %s", passport.Code, passport.Body)
	}

	mobileMoicaIssue := issueMobileMoicaForNationalID(t, h, "did:plc:zzzzzzzzzzzzzzzz", "Z123000000")
	if mobileMoicaIssue.Code != http.StatusConflict {
		t.Fatalf("expected MobileMoica duplicate conflict, got %d %s", mobileMoicaIssue.Code, mobileMoicaIssue.Body)
	}
	if bodyJSON(t, mobileMoicaIssue)["error"] != "duplicate_active_credential" {
		t.Fatalf("unexpected duplicate error: %s", mobileMoicaIssue.Body)
	}
}

func issueMobileMoicaForNationalID(t *testing.T, h *api.Handler, holderDID, nationalID string) *httptest.ResponseRecorder {
	t.Helper()

	start := call(h, http.MethodPost, "/api/v1/vc/mobilemoica/start", map[string]any{
		"holder_did":        holderDID,
		"national_id":       nationalID,
		"consent_version":   "mobilemoica-rp-v1",
		"consent_copy_hash": "sha256:copy-hash",
	})
	// The one-person-one-credential (and pepper-rotation) duplicate check runs
	// at start, where the raw national ID is available. When the person is
	// already bound, start surfaces the conflict directly — return it so the
	// caller can assert on it.
	if start.Code == http.StatusConflict {
		return start
	}
	if start.Code != http.StatusOK {
		t.Fatalf("expected MobileMoica start 200, got %d %s", start.Code, start.Body)
	}
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
