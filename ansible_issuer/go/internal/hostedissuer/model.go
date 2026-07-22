// Package hostedissuer implements the tenant-scoped governance boundary for
// Elix-hosted credential issuers. It never stores tenant root private keys or
// complete issued credentials.
package hostedissuer

import "time"

type TenantStatus string

const (
	TenantDraft  TenantStatus = "draft"
	TenantActive TenantStatus = "active"
	TenantPaused TenantStatus = "paused"
)

type Tenant struct {
	ID                 string       `json:"id"`
	OrganizationDID    string       `json:"organization_did"`
	ServiceSlug        string       `json:"service_slug"`
	Status             TenantStatus `json:"status"`
	Threshold          int          `json:"approval_threshold"`
	AdministratorCount int          `json:"administrator_count"`
	PolicyVersion      int64        `json:"policy_version"`
	CreatedAt          time.Time    `json:"created_at"`
}

type Administrator struct {
	TenantID         string `json:"tenant_id"`
	DID              string `json:"did"`
	Role             string `json:"role"`
	State            string `json:"state"`
	SigningAlgorithm string `json:"signing_algorithm"`
	PublicKeyHex     string `json:"public_key_hex"`
	Custody          string `json:"custody"`
}

type Delegation struct {
	ID              string            `json:"id"`
	TenantID        string            `json:"tenant_id"`
	SigningKeyID    string            `json:"signing_key_id"`
	Sequence        int64             `json:"sequence"`
	CanonicalJSON   []byte            `json:"canonical_payload"`
	PayloadHash     string            `json:"payload_hash"`
	CredentialTypes []string          `json:"credential_types"`
	NotBefore       time.Time         `json:"not_before"`
	ExpiresAt       time.Time         `json:"expires_at"`
	State           string            `json:"state"`
	Approvals       map[string][]byte `json:"approvals"`
}

type SigningKey struct {
	ID              string    `json:"id"`
	TenantID        string    `json:"tenant_id"`
	KMSKeyVersion   string    `json:"kms_key_version"`
	PublicKeyPEM    string    `json:"-"`
	Algorithm       string    `json:"algorithm"`
	ProtectionLevel string    `json:"protection_level"`
	State           string    `json:"state"`
	Version         int64     `json:"version"`
	CreatedAt       time.Time `json:"created_at"`
}

type CredentialTemplate struct {
	ID                string   `json:"id"`
	TenantID          string   `json:"tenant_id"`
	Version           int64    `json:"version"`
	CredentialType    string   `json:"credential_type"`
	ClaimAllowlist    []string `json:"claim_allowlist"`
	ApprovalThreshold int      `json:"approval_threshold"`
	MaxTTLDays        int      `json:"max_ttl_days"`
	Active            bool     `json:"active"`
}

type IssuanceRequest struct {
	ID                   string         `json:"id"`
	TenantID             string         `json:"tenant_id"`
	TemplateID           string         `json:"template_id"`
	TemplateVersion      int64          `json:"template_version"`
	ApplicantPairwiseDID string         `json:"-"`
	ApplicantHash        string         `json:"applicant_hash"`
	PayloadHash          string         `json:"payload_hash"`
	MembershipClass      string         `json:"membership_class"`
	BoardID              string         `json:"board_id"`
	State                string         `json:"state"`
	ApprovalCount        int            `json:"approval_count"`
	PolicySnapshot       map[string]any `json:"policy_snapshot"`
	ExpiresAt            time.Time      `json:"expires_at"`
	CreatedAt            time.Time      `json:"created_at"`
}

type IssuanceApproval struct {
	TenantID         string    `json:"tenant_id"`
	RequestID        string    `json:"request_id"`
	ApproverDID      string    `json:"approver_did"`
	Decision         string    `json:"decision"`
	SignedIntentHash string    `json:"signed_intent_hash"`
	CreatedAt        time.Time `json:"created_at"`
}

type AuditEvent struct {
	ID            string    `json:"id"`
	TenantID      string    `json:"tenant_id"`
	EventType     string    `json:"event_type"`
	ActorDID      string    `json:"actor_did,omitempty"`
	RequestHash   string    `json:"request_hash"`
	PolicyVersion int64     `json:"policy_version"`
	CreatedAt     time.Time `json:"created_at"`
}

type CredentialRecord struct {
	CredentialID        string    `json:"credential_id"`
	TenantID            string    `json:"tenant_id"`
	CredentialHash      string    `json:"credential_hash"`
	CredentialType      string    `json:"credential_type"`
	SubjectPairwiseHash string    `json:"subject_pairwise_hash"`
	IssuedAt            time.Time `json:"issued_at"`
	ExpiresAt           time.Time `json:"expires_at"`
	StatusIndex         int64     `json:"status_index"`
	Status              string    `json:"status"`
	PolicySnapshotHash  string    `json:"policy_snapshot_hash"`
}
