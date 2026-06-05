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
	credentialType             = "TrisAuraHumanityCredential"
	emailCredentialType        = "EmailCredential"
	assuranceLevel             = "tw_natural_person_certificate"
	assuranceMethod            = "tw_fido_or_moica"
	emailAssuranceLevel        = "email_contact"
	emailAssuranceMethod       = "email_otp"
	passportAssuranceLevel     = "passport_document"
	passportAssuranceMethod    = "passport_nfc"
	mobileMoicaAssuranceMethod = "mobilemoica_rp_explicit_disclosure"
	mobileMoicaDisclosureModel = "explicit_rp"
	jurisdiction               = "TW"
	defaultTTLDays             = 90
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
	privKey   ed25519.PrivateKey
	pubKey    ed25519.PublicKey
	ttlDays   int
	store     CredentialStore
}

func NewIssuer(cfg Config, store CredentialStore) (*Issuer, error) {
	seed, err := hex.DecodeString(cfg.PrivKeyHex)
	if err != nil {
		return nil, fmt.Errorf("invalid private key hex: %w", err)
	}
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("private key seed must be %d bytes, got %d", ed25519.SeedSize, len(seed))
	}
	priv := ed25519.NewKeyFromSeed(seed)
	ttl := cfg.TTLDays
	if ttl <= 0 {
		ttl = defaultTTLDays
	}
	return &Issuer{
		issuerDID: cfg.IssuerDID,
		issuerURL: cfg.IssuerURL,
		privKey:   priv,
		pubKey:    priv.Public().(ed25519.PublicKey),
		ttlDays:   ttl,
		store:     store,
	}, nil
}

// Issue builds, signs, and records a TrisAuraHumanityCredential.
// Returns ErrDuplicateActiveCredential if an active credential already exists
// for the given subject commitment.
func (iss *Issuer) Issue(holderDID, subjectCommitment string) (map[string]any, error) {
	if err := iss.store.CheckDuplicate(subjectCommitment); err != nil {
		return nil, err
	}

	return iss.issue(
		credentialType,
		CredentialSubject{
			ID:              holderDID,
			HumanVerified:   true,
			AssuranceLevel:  assuranceLevel,
			AssuranceMethod: assuranceMethod,
			Jurisdiction:    jurisdiction,
		},
		subjectCommitment,
		subjectCommitment,
		"",
	)
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

// IssuePassport builds and signs a passport NFC humanity credential. It does
// not store passport source fields. Duplicate detection is enforced using the
// verifier-produced national ID and passport number commitments.
func (iss *Issuer) IssuePassport(holderDID, nationality, nationalIDHash, passportNumberHash string) (map[string]any, error) {
	if err := iss.store.CheckDuplicatePersonhoodBinding(nationalIDHash, passportNumberHash); err != nil {
		return nil, err
	}

	return iss.issue(
		credentialType,
		CredentialSubject{
			ID:              holderDID,
			HumanVerified:   true,
			AssuranceLevel:  passportAssuranceLevel,
			AssuranceMethod: passportAssuranceMethod,
			Jurisdiction:    jurisdiction,
			Nationality:     nationality,
		},
		"",
		nationalIDHash,
		passportNumberHash,
	)
}

// IssueMobileMoicaRP builds and signs a MobileMoica relying-party humanity
// credential. Raw MobileMoica inputs are processed only before this method; the
// issued VC contains only assurance metadata and the holder DID.
func (iss *Issuer) IssueMobileMoicaRP(holderDID, subjectCommitment string) (map[string]any, error) {
	if err := iss.store.CheckDuplicate(subjectCommitment); err != nil {
		return nil, err
	}

	return iss.issue(
		credentialType,
		CredentialSubject{
			ID:              holderDID,
			HumanVerified:   true,
			AssuranceLevel:  assuranceLevel,
			AssuranceMethod: mobileMoicaAssuranceMethod,
			Jurisdiction:    jurisdiction,
			DisclosureModel: mobileMoicaDisclosureModel,
		},
		subjectCommitment,
		subjectCommitment,
		"",
	)
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
	cred := &Credential{
		Context: []string{
			"https://www.w3.org/ns/credentials/v2",
			"https://trisaura.io/contexts/humanity/v1",
		},
		ID:                fmt.Sprintf("%s/vc/%s", iss.issuerURL, randomHex(16)),
		Type:              []string{"VerifiableCredential", credentialType},
		Issuer:            iss.issuerDID,
		ValidFrom:         now.Format(time.RFC3339),
		ValidUntil:        now.AddDate(0, 0, iss.ttlDays).Format(time.RFC3339),
		CredentialSubject: subject,
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
	proof.ProofValue = multibaseBase58BTCEncode(ed25519.Sign(iss.privKey, hashData))
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
