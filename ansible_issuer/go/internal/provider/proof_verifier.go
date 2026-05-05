package provider

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"
)

var (
	ErrMissingProviderProofValue = errors.New("missing provider proof")
	ErrProviderAudience          = errors.New("invalid provider audience")
	ErrProviderSignature         = errors.New("invalid provider signature")
	ErrProviderExpiry            = errors.New("expired provider assertion")
)

type ProviderAssertion struct {
	State            string
	ReplayID         string
	ProviderSubject  string
	AssuranceContext string
	ExpiresAt        time.Time
}

type ProofVerifier interface {
	Verify(callback map[string]string) (ProviderAssertion, error)
}

type ContractProofConfig struct {
	SharedSecret string
	Audience     string
	Now          func() time.Time
}

type contractProofVerifier struct {
	sharedSecret string
	audience     string
	now          func() time.Time
}

func NewContractProofVerifier(config ContractProofConfig) ProofVerifier {
	now := config.Now
	if now == nil {
		now = time.Now
	}
	return &contractProofVerifier{
		sharedSecret: config.SharedSecret,
		audience:     config.Audience,
		now:          now,
	}
}

func (v *contractProofVerifier) Verify(callback map[string]string) (ProviderAssertion, error) {
	assertion := callback["assertion"]
	signature := callback["signature"]
	subject := callback["provider_subject"]
	audience := callback["audience"]
	expiresAtValue := callback["expires_at"]
	if assertion == "" || signature == "" || subject == "" || audience == "" || expiresAtValue == "" {
		return ProviderAssertion{}, ErrMissingProviderProofValue
	}
	if audience != v.audience {
		return ProviderAssertion{}, ErrProviderAudience
	}
	if !v.validSignature(assertion, signature) {
		return ProviderAssertion{}, ErrProviderSignature
	}

	expiresAt, err := time.Parse(time.RFC3339, expiresAtValue)
	if err != nil {
		return ProviderAssertion{}, ErrProviderExpiry
	}
	if !expiresAt.After(v.now()) {
		return ProviderAssertion{}, ErrProviderExpiry
	}

	replayID := callback["replay_id"]
	if replayID == "" {
		replayID = callback["state"]
	}
	assuranceContext := callback["assurance_context"]
	if assuranceContext == "" {
		assuranceContext = "tw_natural_person_certificate"
	}
	return ProviderAssertion{
		State:            callback["state"],
		ReplayID:         replayID,
		ProviderSubject:  subject,
		AssuranceContext: assuranceContext,
		ExpiresAt:        expiresAt,
	}, nil
}

func (v *contractProofVerifier) validSignature(assertion, signature string) bool {
	got, err := hex.DecodeString(signature)
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(v.sharedSecret))
	mac.Write([]byte(assertion))
	want := mac.Sum(nil)
	return hmac.Equal(got, want)
}
