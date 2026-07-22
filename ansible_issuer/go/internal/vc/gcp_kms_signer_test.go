package vc

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"testing"
)

type fakeKMSClient struct {
	publicPEM string
	private   ed25519.PrivateKey
	algorithm string
	level     string
	tamper    bool
}

func (f fakeKMSClient) PublicKey(context.Context, string) (string, string, string, error) {
	return f.publicPEM, f.algorithm, f.level, nil
}

func (f fakeKMSClient) AsymmetricSign(_ context.Context, _ string, data []byte) ([]byte, string, error) {
	sig := ed25519.Sign(f.private, data)
	if f.tamper {
		sig[0] ^= 1
	}
	return sig, f.level, nil
}

func newFakeKMS(t *testing.T, level string) fakeKMSClient {
	t.Helper()
	pub, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	return fakeKMSClient{
		publicPEM: string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})),
		private:   private,
		algorithm: "EC_SIGN_ED25519",
		level:     level,
	}
}

func TestGCPKMSSignerVerifiesEveryReturnedSignature(t *testing.T) {
	fake := newFakeKMS(t, "HSM")
	signer, err := NewGCPKMSEd25519Signer(context.Background(), "projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1", fake, true)
	if err != nil {
		t.Fatal(err)
	}
	message := []byte("canonical VC payload")
	sig, err := signer.Sign(message)
	if err != nil {
		t.Fatal(err)
	}
	if !ed25519.Verify(signer.PublicKey().(ed25519.PublicKey), message, sig) {
		t.Fatal("signature did not verify")
	}
}

func TestGCPKMSSignerFailsClosedForSoftwareProtection(t *testing.T) {
	fake := newFakeKMS(t, "SOFTWARE")
	if _, err := NewGCPKMSEd25519Signer(context.Background(), "key-version", fake, true); err == nil {
		t.Fatal("expected non-HSM key rejection")
	}
}

func TestGCPKMSSignerRejectsCorruptResponse(t *testing.T) {
	fake := newFakeKMS(t, "HSM")
	fake.tamper = true
	signer, err := NewGCPKMSEd25519Signer(context.Background(), "key-version", fake, true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := signer.Sign([]byte("payload")); err == nil {
		t.Fatal("expected invalid KMS signature rejection")
	}
}
