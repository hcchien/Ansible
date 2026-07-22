package hostedissuer

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"regexp"
	"time"
)

var serviceSlugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{2,47}$`)

type BootstrapRequest struct {
	Type               string    `json:"type"`
	Version            int       `json:"version"`
	OrganizationDID    string    `json:"organization_did"`
	ServiceSlug        string    `json:"service_slug"`
	ApprovalThreshold  int       `json:"approval_threshold"`
	AdministratorCount int       `json:"administrator_count"`
	OwnerDID           string    `json:"owner_did"`
	OwnerPublicKeyHex  string    `json:"owner_public_key_hex"`
	OwnerKeyAlgorithm  string    `json:"owner_key_algorithm"`
	OwnerCustody       string    `json:"owner_custody"`
	IssuedAt           time.Time `json:"issued_at"`
	SignatureHex       string    `json:"signature_hex,omitempty"`
}

type EnrollmentIntent struct {
	Type         string    `json:"type"`
	Version      int       `json:"version"`
	TenantID     string    `json:"tenant_id"`
	AdminDID     string    `json:"admin_did"`
	ClientNonce  string    `json:"client_nonce"`
	IssuedAt     time.Time `json:"issued_at"`
	SignatureHex string    `json:"signature_hex,omitempty"`
}

type ControlPlane struct {
	store Store
	now   func() time.Time
}

func NewControlPlane(store Store, now func() time.Time) *ControlPlane {
	if now == nil {
		now = time.Now
	}
	return &ControlPlane{store: store, now: now}
}

func (c *ControlPlane) Bootstrap(request BootstrapRequest) (Tenant, error) {
	if request.Type != "HostedIssuerBootstrap" || request.Version != 1 ||
		!serviceSlugPattern.MatchString(request.ServiceSlug) || request.OrganizationDID == "" ||
		request.OwnerDID == "" || request.ApprovalThreshold < 1 ||
		request.AdministratorCount < request.ApprovalThreshold || request.AdministratorCount > 15 ||
		request.OwnerKeyAlgorithm != "p256-sha256" || request.OwnerCustody != "hardware" ||
		!withinAdministrativeWindow(request.IssuedAt, c.now()) {
		return Tenant{}, ErrDelegationInvalid
	}
	signature, err := hex.DecodeString(request.SignatureHex)
	if err != nil {
		return Tenant{}, ErrDelegationInvalid
	}
	canonical, err := canonicalBootstrap(request)
	if err != nil {
		return Tenant{}, err
	}
	owner := Administrator{
		DID: request.OwnerDID, SigningAlgorithm: request.OwnerKeyAlgorithm,
		PublicKeyHex: request.OwnerPublicKeyHex, Custody: request.OwnerCustody,
	}
	if err := VerifyAdministratorSignature(owner, canonical, signature); err != nil {
		return Tenant{}, err
	}
	tenantID, err := randomControlPlaneID("tenant")
	if err != nil {
		return Tenant{}, err
	}
	tenant := Tenant{
		ID: tenantID, OrganizationDID: request.OrganizationDID, ServiceSlug: request.ServiceSlug,
		Status: TenantDraft, Threshold: request.ApprovalThreshold, AdministratorCount: request.AdministratorCount,
		PolicyVersion: 1, CreatedAt: c.now().UTC(),
	}
	if err := c.store.BootstrapTenant(tenant, owner); err != nil {
		return Tenant{}, err
	}
	return tenant, nil
}

func (c *ControlPlane) VerifyEnrollmentIntent(intent EnrollmentIntent) error {
	if intent.Type != "IssuerAdminWebAuthnEnrollment" || intent.Version != 1 ||
		intent.TenantID == "" || intent.AdminDID == "" || len(intent.ClientNonce) < 16 ||
		!withinAdministrativeWindow(intent.IssuedAt, c.now()) {
		return ErrWebAuthnCeremony
	}
	admins, err := c.store.Administrators(intent.TenantID)
	if err != nil {
		return err
	}
	var admin *Administrator
	for i := range admins {
		if admins[i].DID == intent.AdminDID && admins[i].State == "active" {
			admin = &admins[i]
			break
		}
	}
	if admin == nil {
		return ErrWebAuthnCeremony
	}
	signature, err := hex.DecodeString(intent.SignatureHex)
	if err != nil {
		return ErrWebAuthnCeremony
	}
	unsigned := intent
	unsigned.SignatureHex = ""
	canonical, err := json.Marshal(unsigned)
	if err != nil {
		return err
	}
	return VerifyAdministratorSignature(*admin, canonical, signature)
}

func canonicalBootstrap(request BootstrapRequest) ([]byte, error) {
	request.SignatureHex = ""
	return json.Marshal(request)
}

func withinAdministrativeWindow(issuedAt, now time.Time) bool {
	if issuedAt.IsZero() {
		return false
	}
	delta := now.Sub(issuedAt)
	return delta >= -30*time.Second && delta <= 5*time.Minute
}

func randomControlPlaneID(prefix string) (string, error) {
	raw := make([]byte, 18)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	if prefix == "" {
		return "", errors.New("id prefix required")
	}
	return prefix + "_" + base64.RawURLEncoding.EncodeToString(raw), nil
}

// RandomControlPlaneIDForAPI creates an opaque public identifier without
// exposing the random-byte construction to HTTP packages.
func RandomControlPlaneIDForAPI(prefix string) (string, error) {
	return randomControlPlaneID(prefix)
}
