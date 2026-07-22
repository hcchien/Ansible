package oid4vci

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"strings"
	"time"
)

var ErrInvalidProof = errors.New("invalid_proof")

type HolderJWK struct {
	KTY string `json:"kty"`
	CRV string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
}

type proofHeader struct {
	Typ string    `json:"typ"`
	Alg string    `json:"alg"`
	JWK HolderJWK `json:"jwk"`
}

type proofClaims struct {
	Audience string `json:"aud"`
	IssuedAt int64  `json:"iat"`
	Nonce    string `json:"nonce"`
}

// VerifyJWTProof implements the OID4VCI jwt proof profile supported by Elix:
// ES256 with an embedded P-256 JWK, issuer audience, fresh nonce, and bounded
// iat. The returned JWK is embedded in the issued credential for holder binding.
func VerifyJWTProof(compact, expectedAudience, expectedNonce string, now time.Time) (HolderJWK, error) {
	parts := strings.Split(compact, ".")
	if len(parts) != 3 || expectedAudience == "" || expectedNonce == "" {
		return HolderJWK{}, ErrInvalidProof
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return HolderJWK{}, ErrInvalidProof
	}
	claimsBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return HolderJWK{}, ErrInvalidProof
	}
	var header proofHeader
	if err := strictJSON(headerBytes, &header); err != nil || header.Typ != "openid4vci-proof+jwt" ||
		header.Alg != "ES256" || header.JWK.KTY != "EC" || header.JWK.CRV != "P-256" {
		return HolderJWK{}, ErrInvalidProof
	}
	var claims proofClaims
	if err := strictJSON(claimsBytes, &claims); err != nil || claims.Audience != expectedAudience ||
		claims.Nonce != expectedNonce || claims.IssuedAt == 0 {
		return HolderJWK{}, ErrInvalidProof
	}
	issuedAt := time.Unix(claims.IssuedAt, 0)
	if issuedAt.After(now.Add(30*time.Second)) || issuedAt.Before(now.Add(-5*time.Minute)) {
		return HolderJWK{}, ErrInvalidProof
	}
	xBytes, errX := base64.RawURLEncoding.DecodeString(header.JWK.X)
	yBytes, errY := base64.RawURLEncoding.DecodeString(header.JWK.Y)
	if errX != nil || errY != nil || len(xBytes) != 32 || len(yBytes) != 32 {
		return HolderJWK{}, ErrInvalidProof
	}
	publicKey := &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(xBytes), Y: new(big.Int).SetBytes(yBytes)}
	if !publicKey.Curve.IsOnCurve(publicKey.X, publicKey.Y) {
		return HolderJWK{}, ErrInvalidProof
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(signature) != 64 {
		return HolderJWK{}, ErrInvalidProof
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(publicKey, digest[:], new(big.Int).SetBytes(signature[:32]), new(big.Int).SetBytes(signature[32:])) {
		return HolderJWK{}, ErrInvalidProof
	}
	return header.JWK, nil
}

func ProofNonce(compact string) (string, error) {
	parts := strings.Split(compact, ".")
	if len(parts) != 3 {
		return "", ErrInvalidProof
	}
	claimsBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", ErrInvalidProof
	}
	var claims proofClaims
	if err := strictJSON(claimsBytes, &claims); err != nil || claims.Nonce == "" {
		return "", ErrInvalidProof
	}
	return claims.Nonce, nil
}

func strictJSON(data []byte, target any) error {
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return ErrInvalidProof
	}
	return nil
}
