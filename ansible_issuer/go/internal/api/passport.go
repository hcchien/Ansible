package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
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
	PersonhoodBindingInput string
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

// PassportDIDControlVerifier proves that the requester controls the private
// key currently registered for the credential holder DID.  A passport proof
// binds a DID into its ZK public inputs, but that alone does not establish that
// the device submitting the proof controls that DID.
type PassportDIDControlVerifier interface {
	VerifyPassportIssue(PassportIssueAuthorization) error
}

// PassportIssueAuthorization is the exact, versioned message that Wallet
// signs before sending a passport issuance request.  Keep this deliberately
// narrow: it contains only protocol metadata and the SHA-256 of the opaque ZK
// proof, never passport or MRZ data.
type PassportIssueAuthorization struct {
	DID                 string
	ChallengeID         string
	ChallengeNonce      string
	ChallengeIssuer     string
	ChallengeScope      string
	Nationality         string
	ZKPProof            string
	ZKPCircuitVersion   string
	VerificationKeyHash string
	SignatureHex        string
}

func (a PassportIssueAuthorization) canonicalPayload() ([]byte, error) {
	proofDigest := sha256.Sum256([]byte(a.ZKPProof))
	return json.Marshal(struct {
		Protocol            string `json:"protocol"`
		Action              string `json:"action"`
		DID                 string `json:"did"`
		ChallengeID         string `json:"challenge_id"`
		ChallengeNonce      string `json:"challenge_nonce"`
		Issuer              string `json:"issuer"`
		Scope               string `json:"scope"`
		Nationality         string `json:"nationality"`
		ZKPProofSHA256      string `json:"zkp_proof_sha256"`
		ZKPCircuitVersion   string `json:"zkp_circuit_version"`
		VerificationKeyHash string `json:"verification_key_hash"`
	}{
		Protocol:            "elix-passport-issuance-v1",
		Action:              "issue",
		DID:                 a.DID,
		ChallengeID:         a.ChallengeID,
		ChallengeNonce:      a.ChallengeNonce,
		Issuer:              a.ChallengeIssuer,
		Scope:               a.ChallengeScope,
		Nationality:         a.Nationality,
		ZKPProofSHA256:      hex.EncodeToString(proofDigest[:]),
		ZKPCircuitVersion:   a.ZKPCircuitVersion,
		VerificationKeyHash: a.VerificationKeyHash,
	})
}

type PassportConfig struct {
	Verifier           PassportBindingVerifier
	DIDControlVerifier PassportDIDControlVerifier
	Challenges         PassportChallengeStore
	IssuerURL          string
}
