package vc

// Credential is the W3C VC JSON structure for a TrisAuraHumanityCredential.
type Credential struct {
	Context           []string          `json:"@context"`
	ID                string            `json:"id"`
	Type              []string          `json:"type"`
	Issuer            string            `json:"issuer"`
	ValidFrom         string            `json:"validFrom"`
	ValidUntil        string            `json:"validUntil"`
	CredentialSubject CredentialSubject `json:"credentialSubject"`
	Proof             *Proof            `json:"proof,omitempty"`
}

// CredentialSubject contains the humanity attestation claims.
// Raw government identity (nationalId, legalName, birthDate) must never appear here.
type CredentialSubject struct {
	ID              string `json:"id"`
	HumanVerified   bool   `json:"humanVerified"`
	AssuranceLevel  string `json:"assuranceLevel"`
	AssuranceMethod string `json:"assuranceMethod"`
	Jurisdiction    string `json:"jurisdiction"`
}

// Proof is the Ed25519Signature2020 proof block.
type Proof struct {
	Type               string `json:"type"`
	Created            string `json:"created"`
	VerificationMethod string `json:"verificationMethod"`
	ProofPurpose       string `json:"proofPurpose"`
	ProofValue         string `json:"proofValue"`
}

// CredentialStatus is the lifecycle state of an issued credential.
type CredentialStatus int

const (
	StatusActive CredentialStatus = iota
	StatusRevoked
)

// record is the issuer's internal entry for a credential.
type record struct {
	credentialID string
	holderDID    string
	commitment   string // HMAC of provider subject — used for duplicate check
	status       CredentialStatus
}
