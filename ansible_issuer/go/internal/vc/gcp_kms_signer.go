package vc

import (
	"context"
	"crypto"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"time"
)

// KMSClient is the narrow Cloud KMS boundary used by hosted tenants. Private
// key bytes are intentionally absent from this interface.
type KMSClient interface {
	PublicKey(ctx context.Context, keyVersion string) (pem string, algorithm string, protectionLevel string, err error)
	AsymmetricSign(ctx context.Context, keyVersion string, data []byte) (signature []byte, protectionLevel string, err error)
}

// GCPKMSEd25519Signer signs raw JCS payload bytes with EC_SIGN_ED25519. Cloud
// KMS PureEdDSA accepts raw data, unlike its P-256/RSA algorithms which accept
// a digest. This distinction is enforced here rather than left to callers.
type GCPKMSEd25519Signer struct {
	keyVersion string
	publicKey  ed25519.PublicKey
	client     KMSClient
	requireHSM bool
}

func NewGCPKMSEd25519Signer(ctx context.Context, keyVersion string, client KMSClient, requireHSM bool) (*GCPKMSEd25519Signer, error) {
	if keyVersion == "" || client == nil {
		return nil, errors.New("KMS key version and client are required")
	}
	publicPEM, algorithm, protection, err := client.PublicKey(ctx, keyVersion)
	if err != nil {
		return nil, fmt.Errorf("get KMS public key: %w", err)
	}
	if algorithm != "EC_SIGN_ED25519" {
		return nil, fmt.Errorf("KMS key must use EC_SIGN_ED25519, got %q", algorithm)
	}
	if requireHSM && protection != "HSM" && protection != "HSM_SINGLE_TENANT" {
		return nil, fmt.Errorf("KMS key protection level %q is not HSM", protection)
	}
	block, _ := pem.Decode([]byte(publicPEM))
	if block == nil {
		return nil, errors.New("KMS public key is not PEM")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse KMS public key: %w", err)
	}
	pub, ok := parsed.(ed25519.PublicKey)
	if !ok || len(pub) != ed25519.PublicKeySize {
		return nil, errors.New("KMS public key is not Ed25519")
	}
	return &GCPKMSEd25519Signer{
		keyVersion: keyVersion,
		publicKey:  append(ed25519.PublicKey(nil), pub...),
		client:     client,
		requireHSM: requireHSM,
	}, nil
}

func (s *GCPKMSEd25519Signer) KeyID() string     { return s.keyVersion }
func (s *GCPKMSEd25519Signer) Algorithm() string { return eddsaJCS2022 }
func (s *GCPKMSEd25519Signer) PublicKey() crypto.PublicKey {
	return append(ed25519.PublicKey(nil), s.publicKey...)
}

func (s *GCPKMSEd25519Signer) Sign(message []byte) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	signature, protection, err := s.client.AsymmetricSign(ctx, s.keyVersion, message)
	if err != nil {
		return nil, fmt.Errorf("KMS asymmetric sign: %w", err)
	}
	if s.requireHSM && protection != "HSM" && protection != "HSM_SINGLE_TENANT" {
		return nil, fmt.Errorf("KMS response protection level %q is not HSM", protection)
	}
	if len(signature) != ed25519.SignatureSize || !ed25519.Verify(s.publicKey, message, signature) {
		return nil, errors.New("KMS returned an invalid signature")
	}
	return signature, nil
}
