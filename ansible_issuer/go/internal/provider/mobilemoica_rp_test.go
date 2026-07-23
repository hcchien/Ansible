package provider_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

type acceptingMobileMoicaVerifier struct{}

type mobileMoicaRoundTripFunc func(*http.Request) (*http.Response, error)

func (f mobileMoicaRoundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return f(request)
}

func (acceptingMobileMoicaVerifier) Verify(
	_ context.Context,
	encoded string,
	expected []byte,
) (string, string, error) {
	if encoded != base64.StdEncoding.EncodeToString(expected) {
		return "", "", provider.ErrMobileMoicaSignedContentInvalid
	}
	return "ephemeral-provider-subject", "provider-replay-1", nil
}

func validMobileMoicaApprovalConfig() provider.MobileMoicaApprovalConfig {
	return provider.MobileMoicaApprovalConfig{
		LegalApprovalID:        "legal-review-2026-05-30",
		PrivacyApprovalID:      "privacy-review-2026-05-30",
		SecurityApprovalID:     "security-review-2026-05-30",
		ConstitutionApprovalID: "constitution-exception-2026-05-30",
	}
}

func validMobileMoicaStartRequest() provider.MobileMoicaStartRequest {
	return provider.MobileMoicaStartRequest{
		OfferID:         "offer-1",
		State:           "state-1",
		HolderDID:       "did:plc:abcdefghijklmnop",
		NationalID:      "Z123000000",
		ConsentVersion:  "mobilemoica-rp-v1",
		ConsentCopyHash: "sha256:copy-hash",
		ReturnURL:       "trisaura://mobilemoica/callback",
		ExpiresAt:       time.Date(2026, 5, 30, 12, 5, 0, 0, time.UTC),
	}
}

const syntheticMobileMoicaChecksumKey = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="

func TestMobileMoicaTicketChecksumPayloadIncludesSignDataForSignOnly(t *testing.T) {
	input := provider.MobileMoicaTicketChecksumInput{
		TransactionID: "txn-1",
		ServiceID:     "svc-1",
		NationalID:    "Z123000000",
		OpCode:        "SIGN",
		OpMode:        "APP2APP",
		Hint:          "hint",
		SignData:      "RE9DX0RJR0VTVA==",
	}

	if got, want := provider.MobileMoicaTicketChecksumPayload(input), "txn-1svc-1Z123000000SIGNAPP2APPhintRE9DX0RJR0VTVA=="; got != want {
		t.Fatalf("unexpected SIGN payload\nwant: %q\n got: %q", want, got)
	}

	input.OpCode = "ATH"
	if got, want := provider.MobileMoicaTicketChecksumPayload(input), "txn-1svc-1Z123000000ATHAPP2APPhint"; got != want {
		t.Fatalf("unexpected ATH payload\nwant: %q\n got: %q", want, got)
	}
}

func TestMobileMoicaResultChecksumPayload(t *testing.T) {
	got := provider.MobileMoicaResultChecksumPayload("txn-1", "svc-1", "ticket-1")

	if want := "txn-1svc-1ticket-1"; got != want {
		t.Fatalf("unexpected result payload\nwant: %q\n got: %q", want, got)
	}
}

func TestMobileMoicaProviderResponseChecksumPayloads(t *testing.T) {
	if got, want := provider.MobileMoicaTicketResponseChecksumPayload("txn-1", "0", "ticket-1"), "txn-10ticket-1"; got != want {
		t.Fatalf("unexpected ticket response payload\nwant: %q\n got: %q", want, got)
	}

	got := provider.MobileMoicaSignResultResponseChecksumPayload("txn-1", "0", "hashed-subject-1", "signed-response-1")
	if want := "txn-10hashed-subject-1signed-response-1"; got != want {
		t.Fatalf("unexpected sign result response payload\nwant: %q\n got: %q", want, got)
	}
}

func TestGenerateMobileMoicaSPChecksumMatchesSyntheticVector(t *testing.T) {
	payload := provider.MobileMoicaTicketChecksumPayload(provider.MobileMoicaTicketChecksumInput{
		TransactionID: "txn-1",
		ServiceID:     "svc-1",
		NationalID:    "Z123000000",
		OpCode:        "SIGN",
		OpMode:        "APP2APP",
		Hint:          "hint",
		SignData:      "RE9DX0RJR0VTVA==",
	})

	checksum, err := provider.GenerateMobileMoicaSPChecksumWithIV(
		payload,
		syntheticMobileMoicaChecksumKey,
		make([]byte, 12),
	)
	if err != nil {
		t.Fatalf("generate checksum: %v", err)
	}

	const want = "000000000000000000000000f710906720376c6e8e4ce5b82ff8613435c2716964d9bd68ada0fc3e83c8b83c021b6ec6e4d5f8323e7ee9387b56d4559ebb7234ea0533315591486f1af4492807c2d2bbd2e980039f1098c39d2fc08a"
	if checksum != want {
		t.Fatalf("unexpected checksum\nwant: %s\n got: %s", want, checksum)
	}
}

func TestGenerateMobileMoicaSPChecksumUsesFreshIVAndVerifies(t *testing.T) {
	payload := provider.MobileMoicaResultChecksumPayload("txn-2", "svc-1", "ticket-2")

	first, err := provider.GenerateMobileMoicaSPChecksum(payload, syntheticMobileMoicaChecksumKey)
	if err != nil {
		t.Fatalf("generate first checksum: %v", err)
	}
	second, err := provider.GenerateMobileMoicaSPChecksum(payload, syntheticMobileMoicaChecksumKey)
	if err != nil {
		t.Fatalf("generate second checksum: %v", err)
	}

	if first == second {
		t.Fatalf("expected fresh IV for repeated checksum generation, got %s", first)
	}
	if err := provider.VerifyMobileMoicaChecksum(payload, first, syntheticMobileMoicaChecksumKey); err != nil {
		t.Fatalf("verify first checksum: %v", err)
	}
	if err := provider.VerifyMobileMoicaChecksum(payload, second, syntheticMobileMoicaChecksumKey); err != nil {
		t.Fatalf("verify second checksum: %v", err)
	}
}

func TestVerifyMobileMoicaChecksumAcceptsChecksumWithNonZeroIV(t *testing.T) {
	payload := provider.MobileMoicaResultChecksumPayload("txn-2", "svc-1", "ticket-2")
	checksum, err := provider.GenerateMobileMoicaSPChecksumWithIV(
		payload,
		syntheticMobileMoicaChecksumKey,
		[]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
	)
	if err != nil {
		t.Fatalf("generate checksum: %v", err)
	}

	if err := provider.VerifyMobileMoicaChecksum(payload, checksum, syntheticMobileMoicaChecksumKey); err != nil {
		t.Fatalf("verify checksum: %v", err)
	}
}

func TestVerifyMobileMoicaChecksumRejectsWrongPayload(t *testing.T) {
	payload := provider.MobileMoicaResultChecksumPayload("txn-2", "svc-1", "ticket-2")
	checksum, err := provider.GenerateMobileMoicaSPChecksum(payload, syntheticMobileMoicaChecksumKey)
	if err != nil {
		t.Fatalf("generate checksum: %v", err)
	}

	err = provider.VerifyMobileMoicaChecksum(payload+"tampered", checksum, syntheticMobileMoicaChecksumKey)
	if !errors.Is(err, provider.ErrMobileMoicaChecksumInvalid) {
		t.Fatalf("expected invalid checksum error, got %v", err)
	}
}

func TestGenerateMobileMoicaSPChecksumRejectsInvalidKey(t *testing.T) {
	_, err := provider.GenerateMobileMoicaSPChecksum("payload", "not-base64")

	if !errors.Is(err, provider.ErrMobileMoicaChecksumConfig) {
		t.Fatalf("expected checksum config error, got %v", err)
	}
}

func TestParseMobileMoicaSPTicketVerifiesDigestAndExtractsQueryFields(t *testing.T) {
	const ticket = "eyJ0cmFuc2FjdGlvbl9pZCI6InR4bi0xIiwib3BfY29kZSI6IlNJR04iLCJvcF9tb2RlIjoiQVBQMkFQUCIsInNwX3NlcnZpY2VfaWQiOiJzdmMtMSIsInNwX3RpY2tldF9pZCI6InRpY2tldC0xIiwiZXhwaXJhdGlvbl90aW1lIjoiMTc2MDAwMDAwMDAwMCIsImhhc2hlZF9pZF9udW0iOiJoYXNoZWQtMSJ9.vnKo5lVX05uDC7cRh_YE2fLYzuvNZ3APBs4YAuDHKUY"

	parsed, err := provider.ParseMobileMoicaSPTicket(ticket)
	if err != nil {
		t.Fatalf("parse ticket: %v", err)
	}

	if parsed.TransactionID != "txn-1" ||
		parsed.OperationCode != "SIGN" ||
		parsed.OperationMode != "APP2APP" ||
		parsed.ServiceID != "svc-1" ||
		parsed.TicketID != "ticket-1" ||
		parsed.HashedIDNumber != "hashed-1" {
		t.Fatalf("unexpected parsed ticket: %+v", parsed)
	}
}

func TestParseMobileMoicaSPTicketRejectsTamperedDigest(t *testing.T) {
	const ticket = "eyJ0cmFuc2FjdGlvbl9pZCI6InR4bi0xIiwib3BfY29kZSI6IlNJR04iLCJvcF9tb2RlIjoiQVBQMkFQUCIsInNwX3NlcnZpY2VfaWQiOiJzdmMtMSIsInNwX3RpY2tldF9pZCI6InRpY2tldC0xIiwiZXhwaXJhdGlvbl90aW1lIjoiMTc2MDAwMDAwMDAwMCIsImhhc2hlZF9pZF9udW0iOiJoYXNoZWQtMSJ9.vnKo5lVX05uDC7cRh_YE2fLYzuvNZ3APBs4YAuDHKUA"

	_, err := provider.ParseMobileMoicaSPTicket(ticket)
	if !errors.Is(err, provider.ErrMobileMoicaTicketInvalid) {
		t.Fatalf("expected invalid ticket error, got %v", err)
	}
}

func TestMobileMoicaApprovalConfigRequiresAllReviewArtifacts(t *testing.T) {
	config := validMobileMoicaApprovalConfig()
	config.PrivacyApprovalID = ""

	err := provider.ValidateMobileMoicaApprovalConfig(config)

	if !errors.Is(err, provider.ErrMobileMoicaApprovalMissing) {
		t.Fatalf("expected missing approval error, got %v", err)
	}
}

func TestContractMobileMoicaRPBrokerBuildsDeepLinkWithoutRawID(t *testing.T) {
	broker := provider.NewContractMobileMoicaRPBroker(provider.ContractMobileMoicaRPConfig{
		ReturnURL: "trisaura://mobilemoica/callback",
		Now:       func() time.Time { return time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC) },
	})

	result, err := broker.Start(context.Background(), validMobileMoicaStartRequest())
	if err != nil {
		t.Fatalf("start contract broker: %v", err)
	}

	parsed, err := url.Parse(result.DeepLinkURL)
	if err != nil {
		t.Fatalf("parse deep link: %v", err)
	}
	if parsed.Scheme != "mobilemoica" {
		t.Fatalf("expected mobilemoica scheme, got %q", parsed.Scheme)
	}
	if result.TicketID == "" {
		t.Fatal("expected synthetic ticket id")
	}
	if strings.Contains(result.DeepLinkURL, "Z123000000") {
		t.Fatalf("deep link leaked national ID: %s", result.DeepLinkURL)
	}
	encodedReturnURL := parsed.Query().Get("rtn_url")
	if strings.Contains(encodedReturnURL, "=") {
		t.Fatalf("return URL must use unpadded Base64URL, got %q", encodedReturnURL)
	}
	returnURL, err := base64.RawURLEncoding.DecodeString(encodedReturnURL)
	if err != nil {
		t.Fatalf("decode Base64URL return URL: %v", err)
	}
	if string(returnURL) != "trisaura://mobilemoica/callback" {
		t.Fatalf("unexpected return URL: %q", string(returnURL))
	}
}

func TestContractMobileMoicaRPBrokerDoesNotAutoVerifyByDefault(t *testing.T) {
	broker := provider.NewContractMobileMoicaRPBroker(provider.ContractMobileMoicaRPConfig{
		ReturnURL: "trisaura://mobilemoica/callback",
		Now:       func() time.Time { return time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC) },
	})
	request := validMobileMoicaStartRequest()
	if _, err := broker.Start(context.Background(), request); err != nil {
		t.Fatalf("start contract broker: %v", err)
	}

	_, err := broker.Verify(context.Background(), request.OfferID, request.State)
	if !errors.Is(err, provider.ErrMobileMoicaResultPending) {
		t.Fatalf("expected pending synthetic result by default, got %v", err)
	}
}

func TestContractMobileMoicaRPBrokerVerifiesSyntheticResult(t *testing.T) {
	broker := provider.NewContractMobileMoicaRPBroker(provider.ContractMobileMoicaRPConfig{
		ReturnURL:  "trisaura://mobilemoica/callback",
		Now:        func() time.Time { return time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC) },
		AutoVerify: true,
	})
	request := validMobileMoicaStartRequest()
	if _, err := broker.Start(context.Background(), request); err != nil {
		t.Fatalf("start contract broker: %v", err)
	}

	result, err := broker.Verify(context.Background(), request.OfferID, request.State)
	if err != nil {
		t.Fatalf("verify contract broker: %v", err)
	}

	if result.ProviderSubject == "" || strings.Contains(result.ProviderSubject, request.NationalID) {
		t.Fatalf("provider subject must be non-empty and redacted: %+v", result)
	}
	if result.AssuranceContext != "mobilemoica_rp_explicit_disclosure" {
		t.Fatalf("unexpected assurance context: %+v", result)
	}
	if !result.ExpiresAt.Equal(request.ExpiresAt) {
		t.Fatalf("unexpected expiry: %+v", result)
	}
}

func TestProductionMobileMoicaRPBrokerFailsClosed(t *testing.T) {
	broker, err := provider.NewProductionMobileMoicaRPBroker(provider.ProductionMobileMoicaRPConfig{})
	if broker != nil || !errors.Is(err, provider.ErrMobileMoicaProductionUnavailable) {
		t.Fatalf("expected fail-closed construction, got broker=%v err=%v", broker, err)
	}
}

func TestProductionMobileMoicaRPBrokerExchangesTicketAndResult(t *testing.T) {
	var signedContent string
	var transactionID string
	transport := mobileMoicaRoundTripFunc(func(r *http.Request) (*http.Response, error) {
		var request map[string]string
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		var payload map[string]string
		switch r.URL.Path {
		case "/ticket":
			transactionID = request["transaction_id"]
			signedContent = request["sign_data"]
			if request["id_num"] != "Z123000000" ||
				request["op_code"] != "SIGN" ||
				request["op_mode"] != "APP2APP" ||
				request["sign_type"] != "PKCS#7" {
				t.Fatalf("unexpected ticket request: %+v", request)
			}
			ticket := syntheticSPTicket(transactionID, "svc-1", "ticket-1")
			checksum, err := provider.GenerateMobileMoicaSPChecksum(
				provider.MobileMoicaTicketResponseChecksumPayload(transactionID, "0", ticket),
				syntheticMobileMoicaChecksumKey,
			)
			if err != nil {
				t.Fatal(err)
			}
			payload = map[string]string{
				"transaction_id": transactionID, "error_code": "0",
				"sp_ticket": ticket, "idp_checksum": checksum,
			}
		case "/result":
			content, err := base64.StdEncoding.DecodeString(signedContent)
			if err != nil {
				t.Fatal(err)
			}
			signed := base64.StdEncoding.EncodeToString(content)
			checksum, err := provider.GenerateMobileMoicaSPChecksum(
				provider.MobileMoicaSignResultResponseChecksumPayload(transactionID, "0", "provider-hash", signed),
				syntheticMobileMoicaChecksumKey,
			)
			if err != nil {
				t.Fatal(err)
			}
			payload = map[string]string{
				"transaction_id": transactionID, "error_code": "0",
				"hashed_id_num": "provider-hash", "signed_response": signed,
				"idp_checksum": checksum,
			}
		default:
			t.Fatalf("unexpected endpoint: %s", r.URL)
		}
		encoded, _ := json.Marshal(payload)
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(bytes.NewReader(encoded)),
			Header:     make(http.Header),
		}, nil
	})

	broker, err := provider.NewProductionMobileMoicaRPBroker(provider.ProductionMobileMoicaRPConfig{
		TicketEndpoint: "https://mobilemoica.example/ticket",
		ResultEndpoint: "https://mobilemoica.example/result",
		ServiceID:      "svc-1",
		EncodedAPIKey:  syntheticMobileMoicaChecksumKey,
		ReturnURL:      "trisaura://mobilemoica/callback",
		HTTPClient:     &http.Client{Transport: transport},
		Verifier:       acceptingMobileMoicaVerifier{},
		Now: func() time.Time {
			return time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatalf("construct production broker: %v", err)
	}
	start, err := broker.Start(context.Background(), validMobileMoicaStartRequest())
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	if strings.Contains(start.DeepLinkURL, "Z123000000") {
		t.Fatal("deep link leaked national ID")
	}
	result, err := broker.Verify(context.Background(), "offer-1", "state-1")
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if result.ReplayID != "provider-replay-1" ||
		result.AssuranceContext != "mobilemoica_rp_explicit_disclosure" {
		t.Fatalf("unexpected result: %+v", result)
	}
}

func syntheticSPTicket(transactionID, serviceID, ticketID string) string {
	payload, _ := json.Marshal(map[string]string{
		"transaction_id":  transactionID,
		"op_code":         "SIGN",
		"op_mode":         "APP2APP",
		"sp_service_id":   serviceID,
		"sp_ticket_id":    ticketID,
		"expiration_time": "2026-05-30T12:05:00Z",
		"hashed_id_num":   "provider-hash",
	})
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(encoded))
	return encoded + "." + base64.RawURLEncoding.EncodeToString(digest[:])
}
