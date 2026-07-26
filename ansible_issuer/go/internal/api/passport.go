package api

import (
	"errors"
	"time"
)

var ErrInvalidPassportProof = errors.New("invalid_passport_proof")

// PassportBindingProof is the proof envelope submitted by Wallet. The Issuer
// treats it as untrusted input until PassportBindingVerifier accepts it.
type PassportBindingProof struct {
	DID                 string
	ChallengeID         string
	ChallengeNonce      string
	ChallengeIssuer     string
	ChallengeScope      string
	Nationality         string
	PassportNumberHash  string
	ZKPProof            string
	ZKPCircuitVersion   string
	VerificationKeyHash string
}

// PassportBindingResult is the verifier-approved binding material the Issuer is
// allowed to persist for duplicate prevention.
type PassportBindingResult struct {
	PersonhoodBindingInput   string
	// Deprecated compatibility field for the original TW-only verifier
	// contract. New verifier runtimes return PersonhoodBindingInput.
	TWPersonBindingInput string
	PassportNumberHash   string
	Nationality          string
	AgeOver18            bool
	VerifiedAt           time.Time
}

type PassportBindingVerifier interface {
	VerifyPassportBinding(PassportBindingProof) (PassportBindingResult, error)
}

type PassportConfig struct {
	Verifier   PassportBindingVerifier
	Challenges PassportChallengeStore
	IssuerURL  string
}
