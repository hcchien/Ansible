package provider_test

import (
	"errors"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestNewProofVerifierAdapterContractModeBuildsVerifier(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	verifier, err := provider.NewProofVerifierAdapter(provider.VerifierAdapterConfig{
		Mode:         provider.VerifierAdapterContract,
		SharedSecret: "provider-secret",
		Audience:     "trisaura-issuer",
		Now:          func() time.Time { return now },
	})
	if err != nil {
		t.Fatalf("new contract adapter: %v", err)
	}

	assertion, err := verifier.Verify(contractCallback("provider-secret", "trisaura-issuer", provider.ProviderAssertion{
		State:           "state-1",
		ProviderSubject: "subject-1",
		ExpiresAt:       now.Add(5 * time.Minute),
	}))
	if err != nil {
		t.Fatalf("verify contract callback: %v", err)
	}
	if assertion.ProviderSubject != "subject-1" {
		t.Fatalf("unexpected assertion: %+v", assertion)
	}
}

func TestNewProofVerifierAdapterProductionModeFailsWithoutTrustAnchors(t *testing.T) {
	_, err := provider.NewProofVerifierAdapter(provider.VerifierAdapterConfig{
		Mode: provider.VerifierAdapterProduction,
	})
	if !errors.Is(err, provider.ErrProductionAdapterConfig) {
		t.Fatalf("expected production config error, got %v", err)
	}
}

func TestNewProofVerifierAdapterProductionModeFailsClosedWhenConfigured(t *testing.T) {
	_, err := provider.NewProofVerifierAdapter(provider.VerifierAdapterConfig{
		Mode:                   provider.VerifierAdapterProduction,
		ProductionTrustAnchors: []string{"tw-provider-root-ca"},
		ProductionAudience:     "trisaura-issuer",
	})
	if !errors.Is(err, provider.ErrProductionAdapterUnavailable) {
		t.Fatalf("expected production unavailable error, got %v", err)
	}
}

func TestNewProofVerifierAdapterRejectsUnknownMode(t *testing.T) {
	_, err := provider.NewProofVerifierAdapter(provider.VerifierAdapterConfig{
		Mode: "surprise",
	})
	if !errors.Is(err, provider.ErrUnknownVerifierAdapterMode) {
		t.Fatalf("expected unknown mode error, got %v", err)
	}
}
