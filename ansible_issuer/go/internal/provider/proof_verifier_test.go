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
