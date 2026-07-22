package vc

import (
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"io"
	"testing"
	"time"
)

func TestBitstringStatusListUsesW3CSizeEncodingAndLeftmostBits(t *testing.T) {
	seed := make([]byte, ed25519.SeedSize)
	_, _ = rand.Read(seed)
	signer, _ := NewEd25519SeedSigner("did:web:issuer#key", hex.EncodeToString(seed))
	list, err := IssueBitstringStatusList(signer, "did:web:issuer", "https://issuer.example/status/revocation/1", "revocation", []CredentialStatusEntry{{Index: 0, Status: "revoked"}, {Index: 7, Status: "revoked"}, {Index: 8, Status: "active"}}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if list.EncodedList[0] != 'u' {
		t.Fatal("missing base64url multibase prefix")
	}
	compressed, err := base64.RawURLEncoding.DecodeString(list.EncodedList[1:])
	if err != nil {
		t.Fatal(err)
	}
	reader, err := gzip.NewReader(bytes.NewReader(compressed))
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	if len(decoded) != 16384 {
		t.Fatalf("got %d bytes, need 16KB", len(decoded))
	}
	if decoded[0] != 0x81 || decoded[1] != 0 {
		t.Fatalf("wrong left-most bit encoding: %x %x", decoded[0], decoded[1])
	}
}
