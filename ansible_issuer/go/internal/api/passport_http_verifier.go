package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

// HTTPPassportBindingVerifier delegates cryptographic verification to the
// pinned ZKPassport verifier runtime. The Issuer still owns policy checks and
// challenge consumption; the verifier is never allowed to issue credentials.
type HTTPPassportBindingVerifier struct {
	endpoint      string
	client        *http.Client
	identityToken func(context.Context, string) (string, error)
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
	verifier := &HTTPPassportBindingVerifier{endpoint: endpoint, client: client}
	// Cloud Run services are private by default. When the Issuer itself runs
	// on Cloud Run, authenticate to the verifier with the workload's identity;
	// local development remains compatible with an explicit local endpoint.
	if strings.TrimSpace(os.Getenv("K_SERVICE")) != "" {
		verifier.identityToken = cloudRunIdentityToken
	}
	return verifier, nil
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
	if v.identityToken != nil {
		token, err := v.identityToken(ctx, v.endpoint)
		if err != nil {
			return PassportBindingResult{}, fmt.Errorf("passport verifier identity: %w", err)
		}
		req.Header.Set("authorization", "Bearer "+token)
	}
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

func cloudRunIdentityToken(ctx context.Context, audience string) (string, error) {
	metadataURL := "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity" +
		"?audience=" + url.QueryEscape(audience) + "&format=full"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, metadataURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Metadata-Flavor", "Google")
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 16<<10))
	token := strings.TrimSpace(string(raw))
	if err != nil || resp.StatusCode != http.StatusOK || len(token) > 16<<10 ||
		len(strings.Split(token, ".")) != 3 {
		return "", errors.New("metadata identity token unavailable")
	}
	return token, nil
}

var _ PassportBindingVerifier = (*HTTPPassportBindingVerifier)(nil)
