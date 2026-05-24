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
	Nationality         string
	NationalIDHash      string
	PassportNumberHash  string
	ZKPProof            string
	ZKPCircuitVersion   string
	VerificationKeyHash string
}

// PassportBindingResult is the verifier-approved binding material the Issuer is
// allowed to persist for duplicate prevention.
type PassportBindingResult struct {
	NationalIDHash     string
	PassportNumberHash string
	Nationality        string
	VerifiedAt         time.Time
}

type PassportBindingVerifier interface {
	VerifyPassportBinding(PassportBindingProof) (PassportBindingResult, error)
}

type PassportConfig struct {
	Verifier PassportBindingVerifier
}
