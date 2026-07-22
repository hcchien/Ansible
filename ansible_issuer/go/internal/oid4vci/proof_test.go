package oid4vci

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"testing"
	"time"
)

func TestVerifyJWTProofBindsAudienceNonceAndP256Key(t *testing.T) {
	now := time.Now().UTC()
	private, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	compact := signProof(t, private, "https://issuer.example/tenants/t", "nonce", now)
	jwk, err := VerifyJWTProof(compact, "https://issuer.example/tenants/t", "nonce", now)
	if err != nil || jwk.CRV != "P-256" {
		t.Fatalf("valid proof rejected: %#v %v", jwk, err)
	}
	if _, err := VerifyJWTProof(compact, "https://other.example", "nonce", now); err == nil {
		t.Fatal("cross-audience proof accepted")
	}
	if _, err := VerifyJWTProof(compact, "https://issuer.example/tenants/t", "other", now); err == nil {
		t.Fatal("wrong nonce proof accepted")
	}
}

func signProof(t *testing.T, private *ecdsa.PrivateKey, audience, nonce string, now time.Time) string {
	t.Helper()
	encode := func(value any) string {
		data, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		return base64.RawURLEncoding.EncodeToString(data)
	}
	pad := func(value *big.Int) string {
		bytes := value.Bytes()
		padded := make([]byte, 32)
		copy(padded[32-len(bytes):], bytes)
		return base64.RawURLEncoding.EncodeToString(padded)
	}
	header := encode(map[string]any{"typ": "openid4vci-proof+jwt", "alg": "ES256", "jwk": map[string]any{"kty": "EC", "crv": "P-256", "x": pad(private.X), "y": pad(private.Y)}})
	claims := encode(map[string]any{"aud": audience, "iat": now.Unix(), "nonce": nonce})
	digest := sha256.Sum256([]byte(header + "." + claims))
	r, s, err := ecdsa.Sign(rand.Reader, private, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	s.FillBytes(signature[32:])
	return header + "." + claims + "." + base64.RawURLEncoding.EncodeToString(signature)
}
