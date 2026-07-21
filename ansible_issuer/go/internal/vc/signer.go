package vc

import (
	"crypto"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// Signer is the issuer's operational signing boundary. Production adapters can
// keep private key material inside KMS/HSM; callers only receive the public key
// and signatures.
type Signer interface {
	KeyID() string
	Algorithm() string
	PublicKey() crypto.PublicKey
	Sign(message []byte) ([]byte, error)
}

// Ed25519SeedSigner is retained for local development, tests, and migration of
// the existing single-issuer deployment. Hosted production tenants must use a
// non-exportable KMS/HSM adapter instead.
type Ed25519SeedSigner struct {
	keyID string
	key   ed25519.PrivateKey
}

func NewEd25519SeedSigner(keyID, seedHex string) (*Ed25519SeedSigner, error) {
	seed, err := hex.DecodeString(seedHex)
	if err != nil {
		return nil, fmt.Errorf("invalid private key hex: %w", err)
	}
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("private key seed must be %d bytes, got %d", ed25519.SeedSize, len(seed))
	}
	return &Ed25519SeedSigner{keyID: keyID, key: ed25519.NewKeyFromSeed(seed)}, nil
}

func (s *Ed25519SeedSigner) KeyID() string     { return s.keyID }
func (s *Ed25519SeedSigner) Algorithm() string { return eddsaJCS2022 }
func (s *Ed25519SeedSigner) PublicKey() crypto.PublicKey {
	return s.key.Public().(ed25519.PublicKey)
}
func (s *Ed25519SeedSigner) Sign(message []byte) ([]byte, error) {
	return s.key.Sign(rand.Reader, message, crypto.Hash(0))
}
