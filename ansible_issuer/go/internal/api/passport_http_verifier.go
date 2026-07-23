package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// HTTPPassportBindingVerifier delegates cryptographic verification to the
// pinned ZKPassport verifier runtime. The Issuer still owns policy checks and
// challenge consumption; the verifier is never allowed to issue credentials.
type HTTPPassportBindingVerifier struct {
	endpoint string
	client   *http.Client
}

func NewHTTPPassportBindingVerifier(endpoint string, client *http.Client) (*HTTPPassportBindingVerifier, error) {
	endpoint = strings.TrimRight(strings.TrimSpace(endpoint), "/")
	if endpoint == "" {
		return nil, errors.New("passport verifier endpoint is required")
	}
	if client == nil {
		// A complete passport query verifies five UltraHonk proofs. This is
		// deliberately longer than ordinary API timeouts, while still bounded.
		client = &http.Client{Timeout: 120 * time.Second}
	}
	return &HTTPPassportBindingVerifier{endpoint: endpoint, client: client}, nil
}

func (v *HTTPPassportBindingVerifier) VerifyPassportBinding(proof PassportBindingProof) (PassportBindingResult, error) {
	payload := struct {
		ProofEnvelope       json.RawMessage `json:"proof_envelope"`
		DID                 string          `json:"did"`
		ChallengeID         string          `json:"challenge_id"`
		ChallengeNonce      string          `json:"challenge_nonce"`
		ChallengeIssuer     string          `json:"challenge_issuer"`
		ChallengeScope      string          `json:"challenge_scope"`
		Nationality         string          `json:"nationality"`
		NationalIDHash      string          `json:"national_id_hash"`
		PassportNumberHash  string          `json:"passport_number_hash"`
		CircuitVersion      string          `json:"circuit_version"`
		VerificationKeyHash string          `json:"verification_key_hash"`
	}{
		ProofEnvelope:       json.RawMessage(proof.ZKPProof),
		DID:                 proof.DID,
		ChallengeID:         proof.ChallengeID,
		ChallengeNonce:      proof.ChallengeNonce,
		ChallengeIssuer:     proof.ChallengeIssuer,
		ChallengeScope:      proof.ChallengeScope,
		Nationality:         proof.Nationality,
		NationalIDHash:      proof.NationalIDHash,
		PassportNumberHash:  proof.PassportNumberHash,
		CircuitVersion:      proof.ZKPCircuitVersion,
		VerificationKeyHash: proof.VerificationKeyHash,
	}
	if !json.Valid(payload.ProofEnvelope) {
		return PassportBindingResult{}, ErrInvalidPassportProof
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return PassportBindingResult{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, v.endpoint+"/verify", bytes.NewReader(body))
	if err != nil {
		return PassportBindingResult{}, err
	}
	req.Header.Set("content-type", "application/json")
	resp, err := v.client.Do(req)
	if err != nil {
		return PassportBindingResult{}, fmt.Errorf("passport verifier: %w", err)
	}
	defer resp.Body.Close()
	limited, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil || resp.StatusCode != http.StatusOK {
		return PassportBindingResult{}, ErrInvalidPassportProof
	}
	var result struct {
		Verified           bool   `json:"verified"`
		Nationality        string `json:"nationality"`
		NationalIDHash     string `json:"national_id_hash"`
		PassportNumberHash string `json:"passport_number_hash"`
	}
	if json.Unmarshal(limited, &result) != nil || !result.Verified {
		return PassportBindingResult{}, ErrInvalidPassportProof
	}
	if result.Nationality != proof.Nationality ||
		result.NationalIDHash == "" ||
		result.PassportNumberHash == "" {
		return PassportBindingResult{}, ErrInvalidPassportProof
	}
	return PassportBindingResult{
		Nationality:        result.Nationality,
		NationalIDHash:     result.NationalIDHash,
		PassportNumberHash: result.PassportNumberHash,
		VerifiedAt:         time.Now().UTC(),
	}, nil
}

var _ PassportBindingVerifier = (*HTTPPassportBindingVerifier)(nil)
