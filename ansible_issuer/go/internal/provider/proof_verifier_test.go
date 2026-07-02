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

// contractCallback builds a fully-signed contract callback. The signature
// covers the canonical assertion payload that binds every security-relevant
// field, matching what the real provider is contracted to sign.
func contractCallback(secret, audience string, a provider.ProviderAssertion) map[string]string {
	payload := provider.ContractAssertionPayload(a, audience)
	return map[string]string{
		"assertion": payload,
		"signature": signedAssertion(secret, payload),
	}
}

func TestContractProofVerifierAcceptsSignedAssertion(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})

	result, err := verifier.Verify(contractCallback("provider-secret", "trisaura-issuer", provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(5 * time.Minute),
	}))
	if err != nil {
		t.Fatalf("verify assertion: %v", err)
	}
	if result.ProviderSubject != "subject-1" || result.AssuranceContext != "tw_natural_person_certificate" {
		t.Fatalf("unexpected result: %+v", result)
	}
	// With no replay_id in the signed payload, the state doubles as the key.
	if result.ReplayID != "state-1" {
		t.Fatalf("expected replay id to default to state, got %q", result.ReplayID)
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
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})
	// Signed for a different audience: signature is valid but bound audience
	// does not match this issuer.
	_, err := verifier.Verify(contractCallback("provider-secret", "other-audience", provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(5 * time.Minute),
	}))
	if err != provider.ErrProviderAudience {
		t.Fatalf("expected wrong audience, got %v", err)
	}
}

func TestContractProofVerifierRejectsInvalidSignature(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})
	payload := provider.ContractAssertionPayload(provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(5 * time.Minute),
	}, "trisaura-issuer")
	_, err := verifier.Verify(map[string]string{
		"assertion": payload,
		"signature": "bad-signature",
	})
	if err != provider.ErrProviderSignature {
		t.Fatalf("expected invalid signature, got %v", err)
	}
}

// TestContractProofVerifierIgnoresUnsignedCallbackFields proves that the trusted
// result is derived only from the signed assertion. An attacker who replays a
// legitimately-signed (assertion, signature) pair but rewrites provider_subject,
// replay_id, state, audience and expires_at in the surrounding map gets the
// ORIGINAL signed values back — the injected values are ignored entirely.
func TestContractProofVerifierIgnoresUnsignedCallbackFields(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})

	callback := contractCallback("provider-secret", "trisaura-issuer", provider.ProviderAssertion{
		State:           "state-legit",
		ReplayID:        "replay-legit",
		ProviderSubject: "subject-legit",
		ExpiresAt:       now.Add(5 * time.Minute),
	})
	// Attacker-controlled, unsigned fields.
	callback["provider_subject"] = "subject-attacker"
	callback["replay_id"] = "replay-attacker"
	callback["state"] = "state-attacker"
	callback["audience"] = "other-audience"
	callback["expires_at"] = "2099-01-01T00:00:00Z"

	result, err := verifier.Verify(callback)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if result.ProviderSubject != "subject-legit" {
		t.Fatalf("verifier trusted unsigned provider_subject: %q", result.ProviderSubject)
	}
	if result.ReplayID != "replay-legit" {
		t.Fatalf("verifier trusted unsigned replay_id: %q", result.ReplayID)
	}
	if result.State != "state-legit" {
		t.Fatalf("verifier trusted unsigned state: %q", result.State)
	}
}

// TestContractProofVerifierRejectsTamperedSignedPayload proves that editing any
// field inside the signed payload (here the provider_subject) while keeping the
// old signature fails verification.
func TestContractProofVerifierRejectsTamperedSignedPayload(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})

	original := provider.ContractAssertionPayload(provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(5 * time.Minute),
	}, "trisaura-issuer")
	sig := signedAssertion("provider-secret", original)

	tampered := provider.ContractAssertionPayload(provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-attacker",
		ExpiresAt:       now.Add(5 * time.Minute),
	}, "trisaura-issuer")

	_, err := verifier.Verify(map[string]string{
		"assertion": tampered,
		"signature": sig,
	})
	if err != provider.ErrProviderSignature {
		t.Fatalf("expected signature failure on tampered payload, got %v", err)
	}
}

func TestContractProofVerifierRejectsExpiredAssertion(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier := provider.NewContractProofVerifier(provider.ContractProofConfig{
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})
	_, err := verifier.Verify(contractCallback("provider-secret", "trisaura-issuer", provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(-time.Minute),
	}))
	if err != provider.ErrProviderExpiry {
		t.Fatalf("expected expiry error, got %v", err)
	}
}
