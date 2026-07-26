package vc

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

const (
	credentialType                  = "TrisAuraHumanityCredential"
	nationalityCredentialType       = "NationalityCredential"
	ageOver18CredentialType         = "AgeOver18Credential"
	emailCredentialType             = "EmailCredential"
	assuranceLevel                  = "tw_natural_person_certificate"
	assuranceMethod                 = "tw_fido_or_moica"
	emailAssuranceLevel             = "email_contact"
	emailAssuranceMethod            = "email_otp"
	passportAssuranceLevel          = "passport_document"
	passportAssuranceMethod         = "passport_nfc"
	mobileMoicaAssuranceMethod      = "mobilemoica_rp_explicit_disclosure"
	mobileMoicaDisclosureModel      = "explicit_rp"
	humanAssuranceVerified          = "verified"
	uniquenessAssuranceStrong       = "strong"
	methodClassGovernmentDocument  = "government_document"
	methodClassGovernmentEID       = "government_eid"
	jurisdiction                    = "TW"
	defaultTTLDays                  = 90
	// credentialStatusType names the issuer's status-endpoint check. The status
	// URL in each credential's credentialStatus resolves via
	// GET /api/v1/vc/status/{id}, which returns the live lifecycle state.
	credentialStatusType = "TrisAuraStatusEndpoint2024"
)

// Config holds issuer configuration.
type Config struct {
	IssuerDID  string
	IssuerURL  string
	PrivKeyHex string // 32-byte Ed25519 seed as lowercase hex
	TTLDays    int
}

// Issuer builds, signs, and tracks Tris-Aura credentials.
type Issuer struct {
	issuerDID string
	issuerURL string
	signer    Signer
	pubKey    ed25519.PublicKey
	ttlDays   int
	store     CredentialStore
}

func NewIssuer(cfg Config, store CredentialStore) (*Issuer, error) {
	signer, err := NewEd25519SeedSigner(cfg.IssuerDID+"#key-1", cfg.PrivKeyHex)
	if err != nil {
		return nil, err
	}
	return NewIssuerWithSigner(cfg, store, signer)
}

// NewIssuerWithSigner builds an issuer around an explicit key-custody
// boundary. Hosted issuer tenants use this with a KMS/HSM-backed signer.
func NewIssuerWithSigner(cfg Config, store CredentialStore, signer Signer) (*Issuer, error) {
	if signer == nil {
		return nil, fmt.Errorf("signer is required")
	}
	if signer.Algorithm() != eddsaJCS2022 {
		return nil, fmt.Errorf("unsupported signer algorithm %q", signer.Algorithm())
	}
	pub, ok := signer.PublicKey().(ed25519.PublicKey)
	if !ok || len(pub) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("signer must expose an Ed25519 public key")
	}
	ttl := cfg.TTLDays
	if ttl <= 0 {
		ttl = defaultTTLDays
	}
	return &Issuer{
		issuerDID: cfg.IssuerDID,
		issuerURL: cfg.IssuerURL,
		signer:    signer,
		pubKey:    append(ed25519.PublicKey(nil), pub...),
		ttlDays:   ttl,
		store:     store,
	}, nil
}

// Issue builds, signs, and records a TrisAuraHumanityCredential.
//
// commitments must be non-empty; commitments[0] is the value written for this
// credential (computed under the primary pepper) and every element is checked
// for an existing active binding. Passing more than one element supports a
// graceful pepper rotation: the same person is recognised whether their prior
// credential was committed under the primary or a previous pepper.
//
// Returns ErrDuplicateActiveCredential if an active credential already exists
// under any supplied commitment.
func (iss *Issuer) Issue(holderDID string, commitments []string) (map[string]any, error) {
	primary := primaryCommitment(commitments)
	if primary == "" {
		return nil, ErrMissingPersonhoodCommitment
	}
	if err := iss.store.CheckDuplicateAny(commitments); err != nil {
		return nil, err
	}

	return iss.issue(
		credentialType,
		CredentialSubject{
			ID:                      holderDID,
			HumanVerified:           true,
			HumanAssurance:          humanAssuranceVerified,
			UniquenessAssurance:     uniquenessAssuranceStrong,
			VerificationMethodClass: methodClassGovernmentEID,
			AssuranceLevel:          assuranceLevel,
			AssuranceMethod:         assuranceMethod,
			Jurisdiction:            jurisdiction,
		},
		primary,
		primary,
		"",
	)
}

// primaryCommitment returns the first non-empty commitment, or "" if none.
func primaryCommitment(commitments []string) string {
	for _, c := range commitments {
		if c != "" {
			return c
		}
	}
	return ""
}

// IssueEmail builds and signs a contactability credential. Email OTP is not a
// personhood proof and does not participate in high-assurance duplicate checks.
func (iss *Issuer) IssueEmail(holderDID string) (map[string]any, error) {
	return iss.issue(
		emailCredentialType,
		CredentialSubject{
			ID:              holderDID,
			EmailVerified:   true,
			AssuranceLevel:  emailAssuranceLevel,
			AssuranceMethod: emailAssuranceMethod,
		},
		"",
		"",
		"",
	)
}

// IssuePassport builds independently presentable passport NFC credentials for
// personhood, nationality, and (when true) the age-over-18 predicate. Passport
// nationality never gates personhood or age issuance. It does not store source
// document fields; duplicate detection uses only verifier-produced commitments.
func (iss *Issuer) IssuePassport(holderDID, nationality, nationalIDHash, passportNumberHash string, ageOver18 bool) ([]map[string]any, error) {
	if nationalIDHash == "" && passportNumberHash == "" {
		return nil, ErrMissingPersonhoodCommitment
	}
	if err := iss.store.CheckDuplicatePersonhoodBinding(nationalIDHash, passportNumberHash); err != nil {
		return nil, err
	}

	humanity, err := iss.issue(
		credentialType,
		CredentialSubject{
			ID:                      holderDID,
			HumanVerified:           true,
			HumanAssurance:          humanAssuranceVerified,
			UniquenessAssurance:     uniquenessAssuranceStrong,
			VerificationMethodClass: methodClassGovernmentDocument,
			AssuranceLevel:          passportAssuranceLevel,
			AssuranceMethod:         passportAssuranceMethod,
		},
		"",
		nationalIDHash,
		passportNumberHash,
	)
	if err != nil {
		return nil, err
	}

	nationalityCredential, err := iss.issue(
		nationalityCredentialType,
		CredentialSubject{
			ID:                  holderDID,
			NationalityVerified: true,
			AssuranceLevel:      passportAssuranceLevel,
			AssuranceMethod:     passportAssuranceMethod,
			Nationality:         nationality,
		},
		"",
		"",
		"",
	)
	if err != nil {
		return nil, err
	}

	credentials := []map[string]any{humanity, nationalityCredential}
	if ageOver18 {
		age, err := iss.issue(
			ageOver18CredentialType,
			CredentialSubject{
				ID:              holderDID,
				AgeOver18:       true,
				AssuranceLevel:  passportAssuranceLevel,
				AssuranceMethod: passportAssuranceMethod,
				Jurisdiction:    jurisdiction,
			},
			"",
			"",
			"",
		)
		if err != nil {
			return nil, err
		}
		credentials = append(credentials, age)
	}
	return credentials, nil
}

// IssueMobileMoicaRP builds and signs a MobileMoica relying-party humanity
// credential. Raw MobileMoica inputs are processed only before this method; the
// issued VC contains only assurance metadata and the holder DID.
func (iss *Issuer) IssueMobileMoicaRP(holderDID string, commitments []string) (map[string]any, error) {
	primary := primaryCommitment(commitments)
	if primary == "" {
		return nil, ErrMissingPersonhoodCommitment
	}
	if err := iss.store.CheckDuplicateAny(commitments); err != nil {
		return nil, err
	}

	return iss.issue(
		credentialType,
		CredentialSubject{
			ID:                      holderDID,
			HumanVerified:           true,
			HumanAssurance:          humanAssuranceVerified,
			UniquenessAssurance:     uniquenessAssuranceStrong,
			VerificationMethodClass: methodClassGovernmentEID,
			AssuranceLevel:          assuranceLevel,
			AssuranceMethod:         mobileMoicaAssuranceMethod,
			Jurisdiction:            jurisdiction,
			DisclosureModel:         mobileMoicaDisclosureModel,
		},
		primary,
		primary,
		"",
	)
}

// CheckDuplicate reports ErrDuplicateActiveCredential if an active credential
// already exists under any of the supplied commitments. It lets callers reject
// a duplicate at verify time (while the raw subject is still available for the
// pepper-rotation dual-check) rather than only at issue time.
func (iss *Issuer) CheckDuplicate(commitments []string) error {
	return iss.store.CheckDuplicateAny(commitments)
}

// Revoke marks an issued credential as revoked so its status endpoint reports
// revoked and its subject may re-enrol. Returns ErrCredentialNotFound when the
// credential id is unknown.
func (iss *Issuer) Revoke(credentialID string) error {
	return iss.store.Revoke(credentialID)
}

// Status returns the lifecycle state of an issued credential.
func (iss *Issuer) Status(credentialID string) (CredentialStatus, bool) {
	return iss.store.Status(credentialID)
}

// CredentialIDFromSuffix reconstructs the full credential id from the hex suffix
// exposed in the credential's id/credentialStatus URLs, so the status endpoint
// (which receives only the suffix path segment) can look the record up.
func (iss *Issuer) CredentialIDFromSuffix(suffix string) string {
	return fmt.Sprintf("%s/vc/%s", iss.issuerURL, suffix)
}

// DIDDocument returns the did:web DID document so external W3C verifiers can
// resolve the issuer's Ed25519 assertion key (#key-1) used in eddsa-jcs-2022
// proofs. Served at https://<host>/.well-known/did.json for did:web:<host>.
func (iss *Issuer) DIDDocument() map[string]any {
	vmID := iss.issuerDID + "#key-1"
	// Multikey publicKeyMultibase = multibase-base58btc(0xed01 || raw ed25519 key),
	// where 0xed01 is the ed25519-pub multicodec varint prefix.
	multibaseKey := multibaseBase58BTCEncode(
		append([]byte{0xed, 0x01}, iss.pubKey...),
	)
	return map[string]any{
		"@context": []string{
			"https://www.w3.org/ns/did/v1",
			"https://w3id.org/security/multikey/v1",
		},
		"id": iss.issuerDID,
		"verificationMethod": []map[string]any{
			{
				"id":                 vmID,
				"type":               "Multikey",
				"controller":         iss.issuerDID,
				"publicKeyMultibase": multibaseKey,
			},
		},
		"assertionMethod": []string{vmID},
	}
}

func (iss *Issuer) issue(
	credentialType string,
	subject CredentialSubject,
	subjectCommitment string,
	nationalIDHash string,
	passportNumberHash string,
) (map[string]any, error) {
	now := time.Now().UTC()
	credHex := randomHex(16)
	cred := &Credential{
		Context: []string{
			"https://www.w3.org/ns/credentials/v2",
			"https://elix.cool/contexts/humanity/v1",
		},
		ID:                fmt.Sprintf("%s/vc/%s", iss.issuerURL, credHex),
		Type:              []string{"VerifiableCredential", credentialType},
		Issuer:            iss.issuerDID,
		ValidFrom:         now.Format(time.RFC3339),
		ValidUntil:        now.AddDate(0, 0, iss.ttlDays).Format(time.RFC3339),
		CredentialSubject: subject,
		CredentialStatus: &CredentialStatus2{
			ID:   fmt.Sprintf("%s/api/v1/vc/status/%s", iss.issuerURL, credHex),
			Type: credentialStatusType,
		},
	}

	proof, err := iss.createDataIntegrityProof(cred, now)
	if err != nil {
		return nil, err
	}
	cred.Proof = proof

	b, err := json.Marshal(cred)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}

	if err := iss.store.add(record{
		credentialID:       cred.ID,
		holderDID:          subject.ID,
		commitment:         subjectCommitment,
		nationalIDHash:     nationalIDHash,
		passportNumberHash: passportNumberHash,
		status:             StatusActive,
	}); err != nil {
		return nil, err
	}

	return out, nil
}

func (iss *Issuer) createDataIntegrityProof(cred *Credential, now time.Time) (*Proof, error) {
	proof := &Proof{
		Context:            cred.Context,
		Type:               dataIntegrityProofType,
		Cryptosuite:        eddsaJCS2022,
		Created:            now.Format(time.RFC3339),
		VerificationMethod: iss.issuerDID + "#key-1",
		ProofPurpose:       "assertionMethod",
	}
	proofConfig, err := proofOptionsMap(proof)
	if err != nil {
		return nil, err
	}
	document, err := credentialDocumentMap(cred)
	if err != nil {
		return nil, err
	}
	hashData, err := dataIntegrityHashData(document, proofConfig)
	if err != nil {
		return nil, err
	}
	signature, err := iss.signer.Sign(hashData)
	if err != nil {
		return nil, fmt.Errorf("sign proof: %w", err)
	}
	proof.ProofValue = multibaseBase58BTCEncode(signature)
	return proof, nil
}

// VerifyProof checks the DataIntegrityProof / eddsa-jcs-2022 proof on a raw credential map.
func (iss *Issuer) VerifyProof(raw map[string]any) bool {
	proofRaw, ok := raw["proof"]
	if !ok {
		return false
	}
	proofMap, ok := proofRaw.(map[string]any)
	if !ok {
		return false
	}
	if proofMap["type"] != dataIntegrityProofType || proofMap["cryptosuite"] != eddsaJCS2022 {
		return false
	}
	proofValue, ok := proofMap["proofValue"].(string)
	if !ok {
		return false
	}
	proofBytes, err := multibaseBase58BTCDecode(proofValue)
	if err != nil {
		return false
	}

	proofOptions := copyMapWithout(proofMap, "proofValue")
	unsecuredDocument := copyMapWithout(raw, "proof")
	if proofContext, ok := proofOptions["@context"]; ok {
		if !proofContextIsDocumentPrefix(raw["@context"], proofContext) {
			return false
		}
		unsecuredDocument["@context"] = proofContext
	}
	hashData, err := dataIntegrityHashData(unsecuredDocument, proofOptions)
	if err != nil {
		return false
	}
	return verifyEd25519Signature(iss.pubKey, hashData, proofBytes)
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
