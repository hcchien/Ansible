package provider

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"
)

var (
	ErrMissingProviderProofValue = errors.New("missing provider proof")
	ErrProviderAudience          = errors.New("invalid provider audience")
	ErrProviderSignature         = errors.New("invalid provider signature")
	ErrProviderExpiry            = errors.New("expired provider assertion")
)

// assertionVersion tags the canonical signed message so the format can evolve.
const assertionVersion = "v1"

// defaultAssuranceContext is used when the signed assertion omits it.
const defaultAssuranceContext = "tw_natural_person_certificate"

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

// ContractAssertionPayload returns the canonical, HMAC-covered message that
// binds every security-relevant field of a provider callback. The provider (and
// the tests that stand in for it) MUST sign exactly this string. Because the
// verifier derives its trusted values by parsing this payload — not by reading
// the surrounding callback map — a valid (assertion, signature) pair cannot be
// replayed with an attacker-chosen provider_subject, replay_id, audience, state
// or expiry: any change alters the payload and breaks the signature.
//
// Fields are '|'-joined in a fixed order and versioned. Empty replay_id is
// permitted (the state then doubles as the replay key downstream).
func ContractAssertionPayload(a ProviderAssertion, audience string) string {
	assuranceContext := a.AssuranceContext
	if assuranceContext == "" {
		assuranceContext = defaultAssuranceContext
	}
	return strings.Join([]string{
		assertionVersion,
		a.State,
		a.ReplayID,
		a.ProviderSubject,
		assuranceContext,
		audience,
		a.ExpiresAt.UTC().Format(time.RFC3339),
	}, "|")
}

func (v *contractProofVerifier) Verify(callback map[string]string) (ProviderAssertion, error) {
	assertion := callback["assertion"]
	signature := callback["signature"]
	if assertion == "" || signature == "" {
		return ProviderAssertion{}, ErrMissingProviderProofValue
	}

	// Verify the HMAC over the whole canonical assertion FIRST, then trust only
	// what the assertion itself says. Anything read from the callback map
	// outside `assertion` is untrusted and must not influence the result.
	if !v.validSignature(assertion, signature) {
		return ProviderAssertion{}, ErrProviderSignature
	}

	parsed, err := parseContractAssertion(assertion)
	if err != nil {
		return ProviderAssertion{}, err
	}

	// The audience is part of the signed payload; binding it here ensures the
	// assertion was minted for this issuer and cannot be replayed at another.
	if parsed.audience != v.audience {
		return ProviderAssertion{}, ErrProviderAudience
	}
	if parsed.assertion.ProviderSubject == "" || parsed.assertion.State == "" {
		return ProviderAssertion{}, ErrMissingProviderProofValue
	}
	if !parsed.assertion.ExpiresAt.After(v.now()) {
		return ProviderAssertion{}, ErrProviderExpiry
	}

	result := parsed.assertion
	if result.ReplayID == "" {
		result.ReplayID = result.State
	}
	if result.AssuranceContext == "" {
		result.AssuranceContext = defaultAssuranceContext
	}
	return result, nil
}

type parsedAssertion struct {
	assertion ProviderAssertion
	audience  string
}

func parseContractAssertion(payload string) (parsedAssertion, error) {
	parts := strings.Split(payload, "|")
	if len(parts) != 7 || parts[0] != assertionVersion {
		return parsedAssertion{}, ErrMissingProviderProofValue
	}
	expiresAt, err := time.Parse(time.RFC3339, parts[6])
	if err != nil {
		return parsedAssertion{}, ErrProviderExpiry
	}
	return parsedAssertion{
		assertion: ProviderAssertion{
			State:            parts[1],
			ReplayID:         parts[2],
			ProviderSubject:  parts[3],
			AssuranceContext: parts[4],
			ExpiresAt:        expiresAt,
		},
		audience: parts[5],
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
