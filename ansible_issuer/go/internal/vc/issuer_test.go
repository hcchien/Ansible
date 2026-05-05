package vc_test

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"testing"

	"github.com/trisaura/ansible_issuer/internal/vc"
)

func newTestIssuer(t *testing.T) *vc.Issuer {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	iss, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.trisaura.io",
		IssuerURL:  "https://issuer.trisaura.io",
		PrivKeyHex: hex.EncodeToString(priv.Seed()),
		TTLDays:    90,
	}, vc.NewStore())
	if err != nil {
		t.Fatal(err)
	}
	return iss
}

func TestIssuer_IssueSigns(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", "commitment-1")
	if err != nil {
		t.Fatal(err)
	}
	if !iss.VerifyProof(raw) {
		t.Fatal("expected proof to be valid")
	}
}

func TestIssuer_CredentialType(t *testing.T) {
	iss := newTestIssuer(t)
	raw, _ := iss.Issue("did:plc:holder1abcdefghij", "commitment-1")
	types, _ := raw["type"].([]any)
	found := false
	for _, v := range types {
		if v == "TrisAuraHumanityCredential" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected TrisAuraHumanityCredential in type, got %v", types)
	}
}

func TestIssuer_NoPIIInCredentialSubject(t *testing.T) {
	iss := newTestIssuer(t)
	raw, _ := iss.Issue("did:plc:holder1abcdefghij", "commitment-1")
	cs, _ := raw["credentialSubject"].(map[string]any)
	for _, prohibited := range []string{"nationalId", "legalName", "birthDate", "email"} {
		if _, ok := cs[prohibited]; ok {
			t.Errorf("credentialSubject must not contain %q", prohibited)
		}
	}
}

func TestIssuer_RefusesDuplicate(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", "commitment-same"); err != nil {
		t.Fatal(err)
	}
	_, err := iss.Issue("did:plc:holder2abcdefghij", "commitment-same")
	if !errors.Is(err, vc.ErrDuplicateActiveCredential) {
		t.Fatalf("expected ErrDuplicateActiveCredential, got %v", err)
	}
}

func TestIssuer_DifferentCommitmentsAllowed(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", "commitment-a"); err != nil {
		t.Fatal(err)
	}
	if _, err := iss.Issue("did:plc:holder2abcdefghij", "commitment-b"); err != nil {
		t.Fatalf("different commitments should be allowed: %v", err)
	}
}

func TestIssuer_InvalidKeyHex(t *testing.T) {
	_, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.trisaura.io",
		IssuerURL:  "https://issuer.trisaura.io",
		PrivKeyHex: "not-hex",
	}, vc.NewStore())
	if err == nil {
		t.Fatal("expected error for invalid key hex")
	}
}
