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
	iss, _ := newTestIssuerWithStore(t)
	return iss
}

func newTestIssuerWithStore(t *testing.T) (*vc.Issuer, *vc.Store) {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	store := vc.NewStore()
	iss, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.trisaura.io",
		IssuerURL:  "https://issuer.trisaura.io",
		PrivKeyHex: hex.EncodeToString(priv.Seed()),
		TTLDays:    90,
	}, store)
	if err != nil {
		t.Fatal(err)
	}
	return iss, store
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

func TestIssuer_IssuePassportCredential(t *testing.T) {
	iss, store := newTestIssuerWithStore(t)
	raw, err := iss.IssuePassport(
		"did:plc:holder1abcdefghij",
		"TWN",
		"national-id-hash-abc123",
		"passport-number-hash-abc123",
	)
	if err != nil {
		t.Fatal(err)
	}
	if !iss.VerifyProof(raw) {
		t.Fatal("expected proof to be valid")
	}

	cs, _ := raw["credentialSubject"].(map[string]any)
	if cs["nationality"] != "TWN" {
		t.Fatalf("expected nationality claim, got %v", cs)
	}
	if cs["assuranceMethod"] != "passport_nfc" {
		t.Fatalf("expected passport_nfc assurance method, got %v", cs)
	}
	for _, prohibited := range []string{"documentNumber", "passportNumber", "passportLocalUniqueId", "passportUid", "passport_uid", "nationalIdHash", "national_id_hash", "passportNumberHash", "passport_number_hash"} {
		if _, ok := cs[prohibited]; ok {
			t.Fatalf("credentialSubject must not contain %q", prohibited)
		}
	}

	binding, ok := store.PersonhoodBindingByNationalIDHash("national-id-hash-abc123")
	if !ok {
		t.Fatal("expected personhood binding to be indexed")
	}
	if binding.HolderDID != "did:plc:holder1abcdefghij" {
		t.Fatalf("expected binding holder DID, got %q", binding.HolderDID)
	}
}

func TestIssuer_IssueMobileMoicaRPCredential(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.IssueMobileMoicaRP(
		"did:plc:holder1abcdefghij",
		"mobilemoica-commitment-1",
	)
	if err != nil {
		t.Fatal(err)
	}
	if !iss.VerifyProof(raw) {
		t.Fatal("expected proof to be valid")
	}

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

	cs, _ := raw["credentialSubject"].(map[string]any)
	if cs["humanVerified"] != true {
		t.Fatalf("expected humanVerified=true, got %v", cs)
	}
	if cs["assuranceMethod"] != "mobilemoica_rp_explicit_disclosure" {
		t.Fatalf("expected mobilemoica assurance method, got %v", cs)
	}
	if cs["disclosureModel"] != "explicit_rp" {
		t.Fatalf("expected explicit_rp disclosure model, got %v", cs)
	}
	if cs["jurisdiction"] != "TW" {
		t.Fatalf("expected TW jurisdiction, got %v", cs)
	}
	for _, prohibited := range []string{
		"nationalId",
		"legalName",
		"certificateSerialNumber",
		"rawProviderAssertion",
		"nationalIdHash",
		"national_id_hash",
		"providerSubject",
		"signedResponse",
	} {
		if _, ok := cs[prohibited]; ok {
			t.Fatalf("credentialSubject must not contain %q", prohibited)
		}
	}
}

func TestIssuer_RefusesDuplicateMobileMoicaRPCommitment(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.IssueMobileMoicaRP("did:plc:holder1abcdefghij", "mobilemoica-commitment-same"); err != nil {
		t.Fatal(err)
	}
	_, err := iss.IssueMobileMoicaRP("did:plc:holder2abcdefghij", "mobilemoica-commitment-same")
	if !errors.Is(err, vc.ErrDuplicateActiveCredential) {
		t.Fatalf("expected ErrDuplicateActiveCredential, got %v", err)
	}
}

func TestIssuer_IssueEmailCredential(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.IssueEmail("did:plc:holder1abcdefghij")
	if err != nil {
		t.Fatal(err)
	}
	if !iss.VerifyProof(raw) {
		t.Fatal("expected proof to be valid")
	}

	types, _ := raw["type"].([]any)
	foundEmail := false
	for _, v := range types {
		if v == "EmailCredential" {
			foundEmail = true
		}
		if v == "TrisAuraHumanityCredential" {
			t.Fatalf("Email OTP must not issue TrisAuraHumanityCredential, got %v", types)
		}
	}
	if !foundEmail {
		t.Fatalf("expected EmailCredential type, got %v", types)
	}
	cs, _ := raw["credentialSubject"].(map[string]any)
	if cs["humanVerified"] == true {
		t.Fatalf("Email OTP must not set humanVerified=true, got %v", cs)
	}
	if cs["assuranceMethod"] != "email_otp" {
		t.Fatalf("expected email_otp assurance method, got %v", cs)
	}
}

func TestIssuer_RefusesDuplicateNationalIDBinding(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", "national-id-hash-abc123"); err != nil {
		t.Fatal(err)
	}
	_, err := iss.IssuePassport(
		"did:plc:holder2abcdefghij",
		"TWN",
		"national-id-hash-abc123",
		"passport-number-hash-other",
	)
	if !errors.Is(err, vc.ErrDuplicatePersonhoodBinding) {
		t.Fatalf("expected ErrDuplicatePersonhoodBinding, got %v", err)
	}
}

func TestIssuer_RefusesDuplicatePassportNumberBinding(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.IssuePassport(
		"did:plc:holder1abcdefghij",
		"TWN",
		"national-id-hash-abc123",
		"passport-number-hash-abc123",
	); err != nil {
		t.Fatal(err)
	}
	_, err := iss.IssuePassport(
		"did:plc:holder2abcdefghij",
		"TWN",
		"national-id-hash-other",
		"passport-number-hash-abc123",
	)
	if !errors.Is(err, vc.ErrDuplicatePersonhoodBinding) {
		t.Fatalf("expected ErrDuplicatePersonhoodBinding, got %v", err)
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
