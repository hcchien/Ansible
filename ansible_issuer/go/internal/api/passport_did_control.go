package api

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var errPassportDIDControl = errors.New("passport did control verification failed")

// HTTPPassportDIDControlVerifier resolves the registered DID verification key
// from a Relay and verifies the holder signature locally.  Relay supplies key
// discovery, not an assertion that issuance is authorised.
type HTTPPassportDIDControlVerifier struct {
	endpoint string
	client   *http.Client
}

func NewHTTPPassportDIDControlVerifier(endpoint string, client *http.Client) (*HTTPPassportDIDControlVerifier, error) {
	endpoint = strings.TrimRight(strings.TrimSpace(endpoint), "/")
	if endpoint == "" {
		return nil, errors.New("passport DID resolver endpoint is required")
	}
	if _, err := url.ParseRequestURI(endpoint); err != nil {
		return nil, fmt.Errorf("passport DID resolver endpoint: %w", err)
	}
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	return &HTTPPassportDIDControlVerifier{endpoint: endpoint, client: client}, nil
}

func (v *HTTPPassportDIDControlVerifier) VerifyPassportIssue(auth PassportIssueAuthorization) error {
	if auth.SignatureHex == "" {
		return errPassportDIDControl
	}
	payload, err := auth.canonicalPayload()
	if err != nil {
		return errPassportDIDControl
	}
	req, err := http.NewRequest(http.MethodGet, v.endpoint+"/api/v1/identity/public-key/"+url.PathEscape(auth.DID), nil)
	if err != nil {
		return errPassportDIDControl
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return errPassportDIDControl
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil || resp.StatusCode != http.StatusOK {
		return errPassportDIDControl
	}
	var key struct {
		DID              string `json:"did"`
		PublicKeyHex     string `json:"public_key_hex"`
		SigningAlgorithm string `json:"signing_algorithm"`
	}
	if json.Unmarshal(raw, &key) != nil || key.DID != auth.DID {
		return errPassportDIDControl
	}
	publicKey, err := hex.DecodeString(key.PublicKeyHex)
	if err != nil {
		return errPassportDIDControl
	}
	signature, err := hex.DecodeString(auth.SignatureHex)
	if err != nil {
		return errPassportDIDControl
	}
	switch key.SigningAlgorithm {
	case "ed25519", "":
		if len(publicKey) != ed25519.PublicKeySize || len(signature) != ed25519.SignatureSize || !ed25519.Verify(publicKey, payload, signature) {
			return errPassportDIDControl
		}
	case "p256-sha256":
		if len(publicKey) != 65 || publicKey[0] != 4 || !elliptic.P256().IsOnCurve(new(big.Int).SetBytes(publicKey[1:33]), new(big.Int).SetBytes(publicKey[33:])) {
			return errPassportDIDControl
		}
		key := &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(publicKey[1:33]), Y: new(big.Int).SetBytes(publicKey[33:])}
		if !ecdsa.VerifyASN1(key, payload, signature) {
			return errPassportDIDControl
		}
	default:
		return errPassportDIDControl
	}
	return nil
}

var _ PassportDIDControlVerifier = (*HTTPPassportDIDControlVerifier)(nil)
