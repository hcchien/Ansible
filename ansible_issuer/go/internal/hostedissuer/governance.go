package hostedissuer

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"time"
)

const delegationType = "IssuerKeyDelegation"

type delegationPayload struct {
	Type            string         `json:"type"`
	Version         int            `json:"version"`
	Issuer          string         `json:"issuer"`
	DelegateKey     string         `json:"delegate_key"`
	Service         string         `json:"service"`
	CredentialTypes []string       `json:"credential_types"`
	NotBefore       time.Time      `json:"not_before"`
	ExpiresAt       time.Time      `json:"expires_at"`
	ApprovalPolicy  approvalPolicy `json:"approval_policy"`
	Sequence        int64          `json:"sequence"`
}

type approvalPolicy struct {
	Threshold      int `json:"threshold"`
	Administrators int `json:"administrators"`
}

// Governance verifies root signatures before persistence. Store methods may
// only receive approvals through this boundary in production wiring.
type Governance struct {
	store Store
	now   func() time.Time
}

func NewGovernance(store Store, now func() time.Time) *Governance {
	if now == nil {
		now = time.Now
	}
	return &Governance{store: store, now: now}
}

func (g *Governance) ApproveDelegation(tenantID, delegationID, adminDID string, canonicalPayload, signature []byte) error {
	admins, err := g.store.Administrators(tenantID)
	if err != nil {
		return err
	}
	var admin *Administrator
	for i := range admins {
		if admins[i].DID == adminDID && admins[i].State == "active" {
			admin = &admins[i]
			break
		}
	}
	if admin == nil {
		return ErrDelegationInvalid
	}
	if err := VerifyAdministratorSignature(*admin, canonicalPayload, signature); err != nil {
		return err
	}
	return g.store.ApproveDelegation(tenantID, delegationID, adminDID, signature)
}

func (g *Governance) ValidateDelegation(tenant Tenant, canonical []byte) (Delegation, error) {
	var payload delegationPayload
	decoder := json.NewDecoder(bytes.NewReader(canonical))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		return Delegation{}, fmt.Errorf("decode delegation: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return Delegation{}, ErrDelegationInvalid
	}
	if payload.Type != delegationType || payload.Version != 1 || payload.Issuer != tenant.OrganizationDID ||
		payload.Sequence < 1 || payload.ApprovalPolicy.Threshold != tenant.Threshold ||
		payload.ApprovalPolicy.Administrators < payload.ApprovalPolicy.Threshold ||
		len(payload.CredentialTypes) == 0 || !payload.ExpiresAt.After(payload.NotBefore) {
		return Delegation{}, ErrDelegationInvalid
	}
	hash := sha256.Sum256(canonical)
	return Delegation{
		TenantID: tenant.ID, Sequence: payload.Sequence, CanonicalJSON: append([]byte(nil), canonical...),
		PayloadHash: hex.EncodeToString(hash[:]), CredentialTypes: append([]string(nil), payload.CredentialTypes...),
		NotBefore: payload.NotBefore, ExpiresAt: payload.ExpiresAt,
	}, nil
}

func verifyRootSignature(admin Administrator, message, signature []byte) error {
	if admin.SigningAlgorithm != "p256-sha256" {
		return fmt.Errorf("unsupported root signing algorithm %q", admin.SigningAlgorithm)
	}
	publicBytes, err := hex.DecodeString(admin.PublicKeyHex)
	if err != nil || len(publicBytes) != 65 || publicBytes[0] != 4 {
		return ErrDelegationInvalid
	}
	x, y := elliptic.Unmarshal(elliptic.P256(), publicBytes)
	if x == nil || y == nil {
		return ErrDelegationInvalid
	}
	digest := sha256.Sum256(message)
	if !ecdsa.VerifyASN1(&ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}, digest[:], signature) {
		return errors.New("invalid root signature")
	}
	return nil
}

// VerifyAdministratorSignature authenticates a canonical administrative
// intent with the administrator's purpose-specific hardware root key.
func VerifyAdministratorSignature(admin Administrator, message, signature []byte) error {
	if admin.Custody != "hardware" {
		return errors.New("root administrator requires hardware custody")
	}
	return verifyRootSignature(admin, message, signature)
}

// VerifyAdministratorIntent verifies an existing active administrator's
// purpose-specific hardware signature over an administrative intent.
func (g *Governance) VerifyAdministratorIntent(tenantID, adminDID string, message, signature []byte) error {
	admins, err := g.store.Administrators(tenantID)
	if err != nil {
		return err
	}
	for i := range admins {
		if admins[i].DID == adminDID && admins[i].State == "active" {
			return VerifyAdministratorSignature(admins[i], message, signature)
		}
	}
	return ErrDelegationInvalid
}
