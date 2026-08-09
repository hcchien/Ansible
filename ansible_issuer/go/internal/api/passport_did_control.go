package api

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/base32"
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
	publicKey, algorithm, err := v.resolveVerificationKey(auth.DID)
	if err != nil {
		return errPassportDIDControl
	}
	signature, err := hex.DecodeString(auth.SignatureHex)
	if err != nil {
		return errPassportDIDControl
	}
	return verifyPassportHolderSignature(publicKey, algorithm, payload, signature)
}

// resolveVerificationKey first uses a self-signed V1 anchor. Newer hardware
// identities do not create that legacy object: their public key and handle are
// registered through the V2 flow. For the V2 path we independently recompute
// the self-certifying DID from that public data before accepting the key.
func (v *HTTPPassportDIDControlVerifier) resolveVerificationKey(did string) ([]byte, string, error) {
	req, err := http.NewRequest(http.MethodGet, v.endpoint+"/api/v1/identity/anchor/"+url.PathEscape(did), nil)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	raw, readErr := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	resp.Body.Close()
	if readErr != nil {
		return nil, "", errPassportDIDControl
	}
	if resp.StatusCode == http.StatusNotFound {
		return v.resolveV2VerificationKey(did)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, "", errPassportDIDControl
	}
	var key struct {
		DID              string  `json:"did"`
		Handle           string  `json:"handle"`
		PublicKeyHex     string  `json:"identity_key"`
		SigningAlgorithm string  `json:"identity_key_algorithm"`
		CustodyClass     string  `json:"custody_class"`
		Reason           string  `json:"reason"`
		PrevAnchorCID    *string `json:"prev_anchor_cid"`
		CanonicalBody    string  `json:"canonical_body"`
		SignatureHex     string  `json:"sig"`
	}
	if json.Unmarshal(raw, &key) != nil || key.DID != did ||
		key.Reason != "initial" || key.PrevAnchorCID != nil ||
		key.DID != deriveInitialDID(key.Handle, key.PublicKeyHex, key.CustodyClass, key.SigningAlgorithm) {
		return nil, "", errPassportDIDControl
	}
	publicKey, err := hex.DecodeString(key.PublicKeyHex)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	anchorSignature, err := hex.DecodeString(key.SignatureHex)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	switch key.SigningAlgorithm {
	case "ed25519", "":
		if len(publicKey) != ed25519.PublicKeySize || len(anchorSignature) != ed25519.SignatureSize || !ed25519.Verify(publicKey, []byte(key.CanonicalBody), anchorSignature) {
			return nil, "", errPassportDIDControl
		}
	case "p256-sha256":
		if len(publicKey) != 65 || publicKey[0] != 4 || !elliptic.P256().IsOnCurve(new(big.Int).SetBytes(publicKey[1:33]), new(big.Int).SetBytes(publicKey[33:])) {
			return nil, "", errPassportDIDControl
		}
		pub := &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(publicKey[1:33]), Y: new(big.Int).SetBytes(publicKey[33:])}
		if !ecdsa.VerifyASN1(pub, []byte(key.CanonicalBody), anchorSignature) {
			return nil, "", errPassportDIDControl
		}
	default:
		return nil, "", errPassportDIDControl
	}
	return publicKey, key.SigningAlgorithm, nil
}

func (v *HTTPPassportDIDControlVerifier) resolveV2VerificationKey(did string) ([]byte, string, error) {
	keyURL := v.endpoint + "/api/v1/identity/public-key/" + url.PathEscape(did)
	handleURL := v.endpoint + "/api/v1/identity/handle/" + url.PathEscape(did)
	keyResp, err := v.client.Get(keyURL)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	keyRaw, keyReadErr := io.ReadAll(io.LimitReader(keyResp.Body, 64<<10))
	keyResp.Body.Close()
	if keyReadErr != nil || keyResp.StatusCode != http.StatusOK {
		return nil, "", errPassportDIDControl
	}
	handleResp, err := v.client.Get(handleURL)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	handleRaw, handleReadErr := io.ReadAll(io.LimitReader(handleResp.Body, 64<<10))
	handleResp.Body.Close()
	if handleReadErr != nil || handleResp.StatusCode != http.StatusOK {
		return nil, "", errPassportDIDControl
	}
	var key struct {
		DID              string `json:"did"`
		PublicKeyHex     string `json:"public_key_hex"`
		SigningAlgorithm string `json:"signing_algorithm"`
	}
	var handle struct {
		DID    string `json:"did"`
		Handle string `json:"handle"`
	}
	if json.Unmarshal(keyRaw, &key) != nil || json.Unmarshal(handleRaw, &handle) != nil ||
		key.DID != did || handle.DID != did || handle.Handle == "" ||
		deriveInitialDID(handle.Handle, key.PublicKeyHex, "hardware", key.SigningAlgorithm) != did {
		return nil, "", errPassportDIDControl
	}
	publicKey, err := hex.DecodeString(key.PublicKeyHex)
	if err != nil {
		return nil, "", errPassportDIDControl
	}
	return publicKey, key.SigningAlgorithm, nil
}

func verifyPassportHolderSignature(publicKey []byte, algorithm string, payload, signature []byte) error {
	switch algorithm {
	case "ed25519", "":
		if len(publicKey) != ed25519.PublicKeySize || len(signature) != ed25519.SignatureSize || !ed25519.Verify(publicKey, payload, signature) {
			return errPassportDIDControl
		}
	case "p256-sha256":
		if len(publicKey) != 65 || publicKey[0] != 4 || !elliptic.P256().IsOnCurve(new(big.Int).SetBytes(publicKey[1:33]), new(big.Int).SetBytes(publicKey[33:])) {
			return errPassportDIDControl
		}
		pub := &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(publicKey[1:33]), Y: new(big.Int).SetBytes(publicKey[33:])}
		if !ecdsa.VerifyASN1(pub, payload, signature) {
			return errPassportDIDControl
		}
	default:
		return errPassportDIDControl
	}
	return nil
}

func deriveInitialDID(handle, publicKeyHex, custodyClass, algorithm string) string {
	if custodyClass == "" {
		custodyClass = "software"
	}
	if algorithm == "" {
		algorithm = "ed25519"
	}
	var body []byte
	if algorithm == "ed25519" {
		body, _ = json.Marshal(struct {
			Method      string `json:"method"`
			V           int    `json:"v"`
			IdentityKey string `json:"identity_key"`
			Handle      string `json:"handle"`
			Custody     string `json:"custody_class"`
		}{"did:elix", 1, publicKeyHex, handle, custodyClass})
	} else {
		body, _ = json.Marshal(struct {
			Method      string `json:"method"`
			V           int    `json:"v"`
			IdentityKey string `json:"identity_key"`
			Algorithm   string `json:"identity_key_algorithm"`
			Handle      string `json:"handle"`
			Custody     string `json:"custody_class"`
		}{"did:elix", 2, publicKeyHex, algorithm, handle, custodyClass})
	}
	digest := sha256.Sum256(body)
	suffix := strings.ToLower(base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(digest[:16]))
	return "did:elix:" + suffix
}

var _ PassportDIDControlVerifier = (*HTTPPassportDIDControlVerifier)(nil)
