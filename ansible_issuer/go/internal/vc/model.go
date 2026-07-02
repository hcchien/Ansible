package vc

// Credential is the W3C VC JSON structure issued by Tris-Aura.
type Credential struct {
	Context           []string           `json:"@context"`
	ID                string             `json:"id"`
	Type              []string           `json:"type"`
	Issuer            string             `json:"issuer"`
	ValidFrom         string             `json:"validFrom"`
	ValidUntil        string             `json:"validUntil"`
	CredentialSubject CredentialSubject  `json:"credentialSubject"`
	CredentialStatus  *CredentialStatus2 `json:"credentialStatus,omitempty"`
	Proof             *Proof             `json:"proof,omitempty"`
}

// CredentialStatus2 is the W3C `credentialStatus` block. It points a verifier at
// the issuer's status endpoint so a revoked credential can be detected after
// issuance. It is part of the signed payload (covered by the eddsa-jcs-2022
// proof), so tampering with the status URL invalidates the proof.
type CredentialStatus2 struct {
	ID   string `json:"id"`
	Type string `json:"type"`
}

// CredentialSubject contains privacy-preserving attestation claims.
// Raw government identity (nationalId, legalName, birthDate) must never appear here.
type CredentialSubject struct {
	ID              string `json:"id"`
	HumanVerified   bool   `json:"humanVerified,omitempty"`
	EmailVerified   bool   `json:"emailVerified,omitempty"`
	AssuranceLevel  string `json:"assuranceLevel,omitempty"`
	AssuranceMethod string `json:"assuranceMethod,omitempty"`
	Jurisdiction    string `json:"jurisdiction,omitempty"`
	Nationality     string `json:"nationality,omitempty"`
	DisclosureModel string `json:"disclosureModel,omitempty"`
}

// Proof is the W3C Data Integrity proof block used by issued credentials.
type Proof struct {
	Context            []string `json:"@context,omitempty"`
	Type               string   `json:"type"`
	Cryptosuite        string   `json:"cryptosuite,omitempty"`
	Created            string   `json:"created"`
	VerificationMethod string   `json:"verificationMethod"`
	ProofPurpose       string   `json:"proofPurpose"`
	ProofValue         string   `json:"proofValue"`
}

// CredentialStatus is the lifecycle state of an issued credential.
type CredentialStatus int

const (
	StatusActive CredentialStatus = iota
	StatusRevoked
)

// String returns the stable wire label for a credential status.
func (s CredentialStatus) String() string {
	switch s {
	case StatusRevoked:
		return "revoked"
	default:
		return "active"
	}
}

// record is the issuer's internal entry for a credential.
type record struct {
	credentialID       string
	holderDID          string
	commitment         string // HMAC of provider subject — used for duplicate check
	nationalIDHash     string // Server-keyed national ID commitment
	passportNumberHash string // Server-keyed passport number commitment
	status             CredentialStatus
}
