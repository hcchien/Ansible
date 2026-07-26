package vc_test

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"path/filepath"
	"strings"
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
	store := vc.NewStore()
	return newTestIssuerUsingStore(t, store), store
}

func newTestIssuerUsingStore(t *testing.T, store *vc.Store) *vc.Issuer {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	iss, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.elix.cool",
		IssuerURL:  "https://issuer.elix.cool",
		PrivKeyHex: hex.EncodeToString(priv.Seed()),
		TTLDays:    90,
	}, store)
	if err != nil {
		t.Fatal(err)
	}
	return iss
}

func TestIssuer_IssueSigns(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatal(err)
	}
	if !iss.VerifyProof(raw) {
		t.Fatal("expected proof to be valid")
	}
}

func TestIssuer_IssueUsesDataIntegrityProof(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatal(err)
	}

	proof, ok := raw["proof"].(map[string]any)
	if !ok {
		t.Fatalf("expected proof object, got %v", raw["proof"])
	}
	if proof["type"] != "DataIntegrityProof" {
		t.Fatalf("expected DataIntegrityProof, got %v", proof)
	}
	if proof["cryptosuite"] != "eddsa-jcs-2022" {
		t.Fatalf("expected eddsa-jcs-2022 cryptosuite, got %v", proof)
	}
	if proof["proofPurpose"] != "assertionMethod" {
		t.Fatalf("expected assertionMethod proof purpose, got %v", proof)
	}
	proofValue, _ := proof["proofValue"].(string)
	if !strings.HasPrefix(proofValue, "z") {
		t.Fatalf("expected multibase base58-btc proofValue, got %q", proofValue)
	}
	if _, err := hex.DecodeString(proofValue); err == nil {
		t.Fatalf("proofValue must not be legacy hex encoding: %q", proofValue)
	}
	if proof["@context"] == nil {
		t.Fatalf("Data Integrity proof must include document context")
	}
}

func TestIssuer_VerifyProofRejectsTamperedCredential(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatal(err)
	}

	cs := raw["credentialSubject"].(map[string]any)
	cs["jurisdiction"] = "US"
	if iss.VerifyProof(raw) {
		t.Fatal("expected proof verification to reject tampered credential")
	}
}

func TestIssuer_VerifyProofRejectsTamperedProofValue(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatal(err)
	}

	proof := raw["proof"].(map[string]any)
	proof["proofValue"] = "z1111111111111111111111111111111111111111111111111111111111111111"
	if iss.VerifyProof(raw) {
		t.Fatal("expected proof verification to reject tampered proofValue")
	}
}

func TestIssuer_CredentialType(t *testing.T) {
	iss := newTestIssuer(t)
	raw, _ := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
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
	raw, _ := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	cs, _ := raw["credentialSubject"].(map[string]any)
	for _, prohibited := range []string{"nationalId", "legalName", "birthDate", "email"} {
		if _, ok := cs[prohibited]; ok {
			t.Errorf("credentialSubject must not contain %q", prohibited)
		}
	}
}

func TestIssuer_HumanityCredentialCarriesStrongUniqueAssurance(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatal(err)
	}
	cs, _ := raw["credentialSubject"].(map[string]any)
	if cs["humanAssurance"] != "verified" {
		t.Fatalf("expected verified human assurance, got %v", cs)
	}
	if cs["uniquenessAssurance"] != "strong" {
		t.Fatalf("expected strong uniqueness assurance, got %v", cs)
	}
	if cs["verificationMethodClass"] != "government_eid" {
		t.Fatalf("expected government_eid method class, got %v", cs)
	}
}

func TestIssuer_StrongAssuranceRequiresPersonhoodCommitment(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", nil); !errors.Is(err, vc.ErrMissingPersonhoodCommitment) {
		t.Fatalf("expected ErrMissingPersonhoodCommitment, got %v", err)
	}
	if _, err := iss.IssuePassport("did:plc:holder1abcdefghij", "TWN", "", "", true); !errors.Is(err, vc.ErrMissingPersonhoodCommitment) {
		t.Fatalf("expected ErrMissingPersonhoodCommitment, got %v", err)
	}
}

func TestIssuer_RefusesDuplicate(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-same"}); err != nil {
		t.Fatal(err)
	}
	_, err := iss.Issue("did:plc:holder2abcdefghij", []string{"commitment-same"})
	if !errors.Is(err, vc.ErrDuplicateActiveCredential) {
		t.Fatalf("expected ErrDuplicateActiveCredential, got %v", err)
	}
}

func TestIssuer_DifferentCommitmentsAllowed(t *testing.T) {
	iss := newTestIssuer(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-a"}); err != nil {
		t.Fatal(err)
	}
	if _, err := iss.Issue("did:plc:holder2abcdefghij", []string{"commitment-b"}); err != nil {
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
		true,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(raw) != 3 {
		t.Fatalf("expected humanity, nationality, and age credentials, got %d", len(raw))
	}
	for _, credential := range raw {
		if !iss.VerifyProof(credential) {
			t.Fatal("expected proof to be valid")
		}
	}

	humanity, _ := raw[0]["credentialSubject"].(map[string]any)
	if humanity["humanVerified"] != true {
		t.Fatalf("expected humanVerified claim, got %v", humanity)
	}
	if humanity["humanAssurance"] != "verified" ||
		humanity["uniquenessAssurance"] != "strong" ||
		humanity["verificationMethodClass"] != "government_document" {
		t.Fatalf("expected strong government-document assurance, got %v", humanity)
	}
	if _, ok := humanity["nationality"]; ok {
		t.Fatalf("humanity credential must not disclose nationality: %v", humanity)
	}
	cs, _ := raw[1]["credentialSubject"].(map[string]any)
	if cs["nationality"] != "TWN" || cs["nationalityVerified"] != true {
		t.Fatalf("expected independently verified nationality claim, got %v", cs)
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

func TestIssuer_IssuePassportCredentialsAreNotTaiwanLocked(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.IssuePassport(
		"did:plc:holder-japan-abcdefghij",
		"JPN",
		"national-id-hash-jpn",
		"passport-number-hash-jpn",
		true,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(raw) != 3 {
		t.Fatalf("expected three credentials, got %d", len(raw))
	}
	nationality, _ := raw[1]["credentialSubject"].(map[string]any)
	if nationality["nationality"] != "JPN" {
		t.Fatalf("expected JPN nationality, got %v", nationality)
	}
	age, _ := raw[2]["credentialSubject"].(map[string]any)
	if age["ageOver18"] != true {
		t.Fatalf("expected nationality-independent age predicate, got %v", age)
	}
}

func TestIssuer_IssueMobileMoicaRPCredential(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.IssueMobileMoicaRP(
		"did:plc:holder1abcdefghij",
		[]string{"mobilemoica-commitment-1"},
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
	if _, err := iss.IssueMobileMoicaRP("did:plc:holder1abcdefghij", []string{"mobilemoica-commitment-same"}); err != nil {
		t.Fatal(err)
	}
	_, err := iss.IssueMobileMoicaRP("did:plc:holder2abcdefghij", []string{"mobilemoica-commitment-same"})
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
	if _, err := iss.Issue("did:plc:holder1abcdefghij", []string{"national-id-hash-abc123"}); err != nil {
		t.Fatal(err)
	}
	_, err := iss.IssuePassport(
		"did:plc:holder2abcdefghij",
		"TWN",
		"national-id-hash-abc123",
		"passport-number-hash-other",
		false,
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
		false,
	); err != nil {
		t.Fatal(err)
	}
	_, err := iss.IssuePassport(
		"did:plc:holder2abcdefghij",
		"TWN",
		"national-id-hash-other",
		"passport-number-hash-abc123",
		false,
	)
	if !errors.Is(err, vc.ErrDuplicatePersonhoodBinding) {
		t.Fatalf("expected ErrDuplicatePersonhoodBinding, got %v", err)
	}
}

func TestIssuer_FileStorePersistsActivePersonhoodBinding(t *testing.T) {
	path := filepath.Join(t.TempDir(), "personhood-bindings.json")
	store, err := vc.NewFileStore(path)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}
	iss := newTestIssuerUsingStore(t, store)
	if _, err := iss.IssueMobileMoicaRP(
		"did:plc:holder1abcdefghij",
		[]string{"tw-national-id-commitment-abc123"},
	); err != nil {
		t.Fatal(err)
	}

	reopened, err := vc.NewFileStore(path)
	if err != nil {
		t.Fatalf("reopen file store: %v", err)
	}
	restartedIssuer := newTestIssuerUsingStore(t, reopened)
	_, err = restartedIssuer.IssuePassport(
		"did:plc:holder2abcdefghij",
		"TWN",
		"tw-national-id-commitment-abc123",
		"passport-number-hash-other",
		false,
	)
	if !errors.Is(err, vc.ErrDuplicatePersonhoodBinding) {
		t.Fatalf("expected persisted duplicate personhood binding, got %v", err)
	}
}

func TestIssuer_InvalidKeyHex(t *testing.T) {
	_, err := vc.NewIssuer(vc.Config{
		IssuerDID:  "did:web:issuer.elix.cool",
		IssuerURL:  "https://issuer.elix.cool",
		PrivKeyHex: "not-hex",
	}, vc.NewStore())
	if err == nil {
		t.Fatal("expected error for invalid key hex")
	}
}

func TestIssuer_DualCheckMatchesPreviousPepperCommitment(t *testing.T) {
	// Person enrolled under a legacy commitment value.
	iss, _ := newTestIssuerWithStore(t)
	if _, err := iss.Issue("did:plc:holder1abcdefghij", []string{"legacy-commitment"}); err != nil {
		t.Fatalf("first issue: %v", err)
	}

	// A later issuance for the same person supplies both the new-pepper primary
	// commitment (element 0, never seen) and the legacy commitment. The dual
	// check across both must catch the duplicate.
	_, err := iss.Issue("did:plc:holder2abcdefghij", []string{"new-primary-commitment", "legacy-commitment"})
	if !errors.Is(err, vc.ErrDuplicateActiveCredential) {
		t.Fatalf("expected duplicate via dual-check, got %v", err)
	}
}

func TestIssuer_RevokeFreesCommitmentForReEnrolment(t *testing.T) {
	iss, _ := newTestIssuerWithStore(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	credID := raw["id"].(string)

	// Duplicate is blocked while active.
	if _, err := iss.Issue("did:plc:holder2abcdefghij", []string{"commitment-1"}); !errors.Is(err, vc.ErrDuplicateActiveCredential) {
		t.Fatalf("expected duplicate while active, got %v", err)
	}

	// Status reflects active, then revoked.
	if st, ok := iss.Status(credID); !ok || st != vc.StatusActive {
		t.Fatalf("expected active status, got %v ok=%v", st, ok)
	}
	if err := iss.Revoke(credID); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if st, ok := iss.Status(credID); !ok || st != vc.StatusRevoked {
		t.Fatalf("expected revoked status, got %v ok=%v", st, ok)
	}

	// After revocation the same commitment may re-enrol.
	if _, err := iss.Issue("did:plc:holder2abcdefghij", []string{"commitment-1"}); err != nil {
		t.Fatalf("expected re-enrolment after revoke, got %v", err)
	}
}

func TestIssuer_RevokeUnknownReturnsNotFound(t *testing.T) {
	iss := newTestIssuer(t)
	if err := iss.Revoke("https://issuer.elix.cool/vc/does-not-exist"); !errors.Is(err, vc.ErrCredentialNotFound) {
		t.Fatalf("expected ErrCredentialNotFound, got %v", err)
	}
}

func TestIssuer_CredentialStatusRoundTripsThroughProof(t *testing.T) {
	iss := newTestIssuer(t)
	raw, err := iss.Issue("did:plc:holder1abcdefghij", []string{"commitment-1"})
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	// credentialStatus is part of the signed payload; the proof must still
	// verify with it present.
	if _, ok := raw["credentialStatus"].(map[string]any); !ok {
		t.Fatalf("issued credential missing credentialStatus: %v", raw)
	}
	if !iss.VerifyProof(raw) {
		t.Fatal("proof did not round-trip with credentialStatus present")
	}
}
