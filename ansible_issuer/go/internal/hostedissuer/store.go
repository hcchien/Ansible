package hostedissuer

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"sort"
	"sync"
	"time"
)

var (
	ErrNotFound          = errors.New("not_found")
	ErrTenantScope       = errors.New("tenant_scope_violation")
	ErrThresholdNotMet   = errors.New("approval_threshold_not_met")
	ErrDelegationReplay  = errors.New("delegation_sequence_replay")
	ErrDelegationInvalid = errors.New("delegation_invalid")
)

// Store requires TenantID on every object lookup/mutation. Implementations
// must never expose a global GetByID that could accidentally omit tenant scope.
type Store interface {
	BootstrapTenant(Tenant, Administrator) error
	CreateTenant(Tenant) error
	Tenant(tenantID string) (Tenant, error)
	PutAdministrator(tenantID string, administrator Administrator) error
	Administrators(tenantID string) ([]Administrator, error)
	PutSigningKey(tenantID string, key SigningKey) error
	SigningKey(tenantID, keyID string) (SigningKey, error)
	ReserveStatusIndex(tenantID string) (int64, error)
	PutCredentialRecord(tenantID string, record CredentialRecord) error
	SetCredentialStatus(tenantID, credentialID, status string) error
	CredentialRecords(tenantID string) ([]CredentialRecord, error)
	PutCredentialTemplate(tenantID string, template CredentialTemplate) error
	ActiveCredentialTemplate(tenantID, templateID string) (CredentialTemplate, error)
	PutIssuanceRequest(tenantID string, request IssuanceRequest) error
	IssuanceRequest(tenantID, requestID string) (IssuanceRequest, error)
	IssuanceRequests(tenantID, state string) ([]IssuanceRequest, error)
	DecideIssuanceRequest(tenantID string, approval IssuanceApproval, threshold int) (IssuanceRequest, error)
	ConsumeApprovedIssuanceRequest(tenantID, requestID string, now time.Time) (IssuanceRequest, error)
	ProposeDelegation(tenantID string, delegation Delegation) error
	ApproveDelegation(tenantID, delegationID, adminDID string, signature []byte) error
	ActivateDelegation(tenantID, delegationID string, now time.Time) error
	RevokeDelegation(tenantID, delegationID string, now time.Time) error
	ActiveDelegation(tenantID string, now time.Time) (Delegation, error)
	AppendAudit(tenantID string, event AuditEvent) error
	Audit(tenantID string) ([]AuditEvent, error)
}

func (s *MemoryStore) BootstrapTenant(tenant Tenant, owner Administrator) error {
	if tenant.AdministratorCount == 0 {
		tenant.AdministratorCount = tenant.Threshold
	}
	if tenant.ID == "" || tenant.OrganizationDID == "" || tenant.ServiceSlug == "" || tenant.Threshold < 1 ||
		tenant.AdministratorCount < tenant.Threshold ||
		owner.DID == "" || owner.Custody != "hardware" || owner.SigningAlgorithm != "p256-sha256" {
		return ErrDelegationInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.tenants[tenant.ID]; exists {
		return fmt.Errorf("tenant exists")
	}
	owner.TenantID = tenant.ID
	owner.Role = "owner"
	owner.State = "active"
	s.tenants[tenant.ID] = tenant
	s.admins[tenant.ID] = map[string]Administrator{owner.DID: owner}
	return nil
}

type MemoryStore struct {
	mu            sync.RWMutex
	tenants       map[string]Tenant
	admins        map[string]map[string]Administrator
	delegations   map[string]map[string]Delegation
	audit         map[string][]AuditEvent
	signingKeys   map[string]map[string]SigningKey
	credentials   map[string]map[string]CredentialRecord
	templates     map[string]map[string]CredentialTemplate
	requests      map[string]map[string]IssuanceRequest
	approvals     map[string]map[string]map[string]IssuanceApproval
	statusIndexes map[string]map[int64]bool
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		tenants: make(map[string]Tenant), admins: make(map[string]map[string]Administrator),
		delegations: make(map[string]map[string]Delegation), audit: make(map[string][]AuditEvent),
		signingKeys: make(map[string]map[string]SigningKey),
		credentials: make(map[string]map[string]CredentialRecord), statusIndexes: make(map[string]map[int64]bool),
		templates: make(map[string]map[string]CredentialTemplate), requests: make(map[string]map[string]IssuanceRequest),
		approvals: make(map[string]map[string]map[string]IssuanceApproval),
	}
}

func (s *MemoryStore) ReserveStatusIndex(tenantID string) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return 0, ErrNotFound
	}
	if s.statusIndexes[tenantID] == nil {
		s.statusIndexes[tenantID] = make(map[int64]bool)
	}
	for attempt := 0; attempt < 256; attempt++ {
		value, err := rand.Int(rand.Reader, big.NewInt(131072))
		if err != nil {
			return 0, err
		}
		index := value.Int64()
		if !s.statusIndexes[tenantID][index] {
			s.statusIndexes[tenantID][index] = true
			return index, nil
		}
	}
	return 0, errors.New("status list index allocation collision limit")
}

func (s *MemoryStore) PutCredentialRecord(tenantID string, record CredentialRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if record.TenantID != "" && record.TenantID != tenantID {
		return ErrTenantScope
	}
	if !s.statusIndexes[tenantID][record.StatusIndex] {
		return ErrDelegationInvalid
	}
	record.TenantID = tenantID
	if s.credentials[tenantID] == nil {
		s.credentials[tenantID] = make(map[string]CredentialRecord)
	}
	if _, exists := s.credentials[tenantID][record.CredentialID]; exists {
		if s.credentials[tenantID][record.CredentialID].CredentialHash == record.CredentialHash {
			return nil
		}
		return ErrDelegationInvalid
	}
	s.credentials[tenantID][record.CredentialID] = record
	return nil
}

func (s *MemoryStore) SetCredentialStatus(tenantID, credentialID, status string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	record, ok := s.credentials[tenantID][credentialID]
	if !ok {
		return ErrNotFound
	}
	if status != "active" && status != "revoked" && status != "suspended" {
		return ErrDelegationInvalid
	}
	record.Status = status
	s.credentials[tenantID][credentialID] = record
	return nil
}

func (s *MemoryStore) CredentialRecords(tenantID string) ([]CredentialRecord, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return nil, ErrNotFound
	}
	result := make([]CredentialRecord, 0, len(s.credentials[tenantID]))
	for _, record := range s.credentials[tenantID] {
		result = append(result, record)
	}
	return result, nil
}

func (s *MemoryStore) PutCredentialTemplate(tenantID string, template CredentialTemplate) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return ErrNotFound
	}
	if template.TenantID != "" && template.TenantID != tenantID {
		return ErrTenantScope
	}
	if template.ID == "" || template.Version < 1 || template.CredentialType == "" ||
		template.ApprovalThreshold < 1 || template.MaxTTLDays < 1 {
		return ErrDelegationInvalid
	}
	if s.templates[tenantID] == nil {
		s.templates[tenantID] = make(map[string]CredentialTemplate)
	}
	for key, current := range s.templates[tenantID] {
		if current.ID == template.ID {
			if template.Version <= current.Version {
				return ErrDelegationReplay
			}
			if template.Active {
				current.Active = false
				s.templates[tenantID][key] = current
			}
		}
	}
	template.TenantID = tenantID
	s.templates[tenantID][fmt.Sprintf("%s:%d", template.ID, template.Version)] = template
	return nil
}

func (s *MemoryStore) ActiveCredentialTemplate(tenantID, templateID string) (CredentialTemplate, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, template := range s.templates[tenantID] {
		if template.ID == templateID && template.Active {
			return template, nil
		}
	}
	return CredentialTemplate{}, ErrNotFound
}

func (s *MemoryStore) PutIssuanceRequest(tenantID string, request IssuanceRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if request.TenantID != "" && request.TenantID != tenantID {
		return ErrTenantScope
	}
	if request.ID == "" || request.TemplateID == "" || request.TemplateVersion < 1 ||
		request.ApplicantPairwiseDID == "" || request.PayloadHash == "" || request.ExpiresAt.IsZero() {
		return ErrDelegationInvalid
	}
	if s.requests[tenantID] == nil {
		s.requests[tenantID] = make(map[string]IssuanceRequest)
	}
	if _, exists := s.requests[tenantID][request.ID]; exists {
		return ErrDelegationReplay
	}
	request.TenantID = tenantID
	request.State = "pending"
	s.requests[tenantID][request.ID] = request
	return nil
}

func (s *MemoryStore) IssuanceRequest(tenantID, requestID string) (IssuanceRequest, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	request, ok := s.requests[tenantID][requestID]
	if !ok {
		return IssuanceRequest{}, ErrNotFound
	}
	return request, nil
}

func (s *MemoryStore) IssuanceRequests(tenantID, state string) ([]IssuanceRequest, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return nil, ErrNotFound
	}
	result := make([]IssuanceRequest, 0, len(s.requests[tenantID]))
	for _, request := range s.requests[tenantID] {
		if state != "" && request.State != state {
			continue
		}
		for _, approval := range s.approvals[tenantID][request.ID] {
			if approval.Decision == "approve" {
				request.ApprovalCount++
			}
		}
		result = append(result, request)
	}
	sort.Slice(result, func(a, b int) bool {
		return result[a].CreatedAt.After(result[b].CreatedAt)
	})
	return result, nil
}

func (s *MemoryStore) DecideIssuanceRequest(tenantID string, approval IssuanceApproval, threshold int) (IssuanceRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	request, ok := s.requests[tenantID][approval.RequestID]
	admin, adminOK := s.admins[tenantID][approval.ApproverDID]
	if !ok || !adminOK || admin.State != "active" || request.State != "pending" ||
		(approval.Decision != "approve" && approval.Decision != "deny") || approval.SignedIntentHash == "" {
		return IssuanceRequest{}, ErrDelegationInvalid
	}
	if s.approvals[tenantID] == nil {
		s.approvals[tenantID] = make(map[string]map[string]IssuanceApproval)
	}
	if s.approvals[tenantID][request.ID] == nil {
		s.approvals[tenantID][request.ID] = make(map[string]IssuanceApproval)
	}
	if existing, exists := s.approvals[tenantID][request.ID][approval.ApproverDID]; exists {
		if existing.Decision == approval.Decision && existing.SignedIntentHash == approval.SignedIntentHash {
			return request, nil
		}
		return IssuanceRequest{}, ErrDelegationReplay
	}
	approval.TenantID = tenantID
	s.approvals[tenantID][request.ID][approval.ApproverDID] = approval
	if approval.Decision == "deny" {
		request.State = "denied"
	} else {
		approved := 0
		for _, decision := range s.approvals[tenantID][request.ID] {
			if decision.Decision == "approve" {
				approved++
			}
		}
		if approved >= threshold {
			request.State = "approved"
		}
	}
	s.requests[tenantID][request.ID] = request
	return request, nil
}

func (s *MemoryStore) ConsumeApprovedIssuanceRequest(tenantID, requestID string, now time.Time) (IssuanceRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	request, ok := s.requests[tenantID][requestID]
	if !ok || request.State != "approved" || !now.Before(request.ExpiresAt) {
		return IssuanceRequest{}, ErrDelegationInvalid
	}
	request.State = "offered"
	s.requests[tenantID][requestID] = request
	return request, nil
}

func (s *MemoryStore) PutSigningKey(tenantID string, key SigningKey) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return ErrNotFound
	}
	if key.TenantID != "" && key.TenantID != tenantID {
		return ErrTenantScope
	}
	key.TenantID = tenantID
	if s.signingKeys[tenantID] == nil {
		s.signingKeys[tenantID] = make(map[string]SigningKey)
	}
	if _, exists := s.signingKeys[tenantID][key.ID]; exists {
		return ErrDelegationInvalid
	}
	s.signingKeys[tenantID][key.ID] = key
	return nil
}

func (s *MemoryStore) SigningKey(tenantID, keyID string) (SigningKey, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	key, ok := s.signingKeys[tenantID][keyID]
	if !ok {
		return SigningKey{}, ErrNotFound
	}
	return key, nil
}

func (s *MemoryStore) CreateTenant(tenant Tenant) error {
	if tenant.AdministratorCount == 0 {
		tenant.AdministratorCount = tenant.Threshold
	}
	if tenant.ID == "" || tenant.OrganizationDID == "" || tenant.ServiceSlug == "" || tenant.Threshold < 1 {
		return ErrDelegationInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.tenants[tenant.ID]; exists {
		return fmt.Errorf("tenant exists")
	}
	s.tenants[tenant.ID] = tenant
	return nil
}

func (s *MemoryStore) Tenant(tenantID string) (Tenant, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	tenant, ok := s.tenants[tenantID]
	if !ok {
		return Tenant{}, ErrNotFound
	}
	return tenant, nil
}

func (s *MemoryStore) PutAdministrator(tenantID string, administrator Administrator) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return ErrNotFound
	}
	if administrator.TenantID != "" && administrator.TenantID != tenantID {
		return ErrTenantScope
	}
	tenant := s.tenants[tenantID]
	if _, exists := s.admins[tenantID][administrator.DID]; !exists && tenant.AdministratorCount > 0 &&
		len(s.admins[tenantID]) >= tenant.AdministratorCount {
		return ErrThresholdNotMet
	}
	administrator.TenantID = tenantID
	if s.admins[tenantID] == nil {
		s.admins[tenantID] = make(map[string]Administrator)
	}
	s.admins[tenantID][administrator.DID] = administrator
	return nil
}

func (s *MemoryStore) Administrators(tenantID string) ([]Administrator, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return nil, ErrNotFound
	}
	result := make([]Administrator, 0, len(s.admins[tenantID]))
	for _, admin := range s.admins[tenantID] {
		result = append(result, admin)
	}
	return result, nil
}

func (s *MemoryStore) ProposeDelegation(tenantID string, delegation Delegation) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return ErrNotFound
	}
	if delegation.TenantID != "" && delegation.TenantID != tenantID {
		return ErrTenantScope
	}
	if delegation.ID == "" || delegation.Sequence < 1 || delegation.PayloadHash == "" || delegation.ExpiresAt.IsZero() {
		return ErrDelegationInvalid
	}
	for _, existing := range s.delegations[tenantID] {
		if delegation.Sequence <= existing.Sequence {
			return ErrDelegationReplay
		}
	}
	delegation.TenantID = tenantID
	delegation.State = "proposed"
	delegation.Approvals = make(map[string][]byte)
	if s.delegations[tenantID] == nil {
		s.delegations[tenantID] = make(map[string]Delegation)
	}
	s.delegations[tenantID][delegation.ID] = delegation
	return nil
}

func (s *MemoryStore) ApproveDelegation(tenantID, delegationID, adminDID string, signature []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delegation, ok := s.delegations[tenantID][delegationID]
	if !ok {
		return ErrNotFound
	}
	admin, ok := s.admins[tenantID][adminDID]
	if !ok || admin.State != "active" || len(signature) == 0 {
		return ErrDelegationInvalid
	}
	delegation.Approvals[adminDID] = append([]byte(nil), signature...)
	s.delegations[tenantID][delegationID] = delegation
	return nil
}

func (s *MemoryStore) ActivateDelegation(tenantID, delegationID string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant, ok := s.tenants[tenantID]
	if !ok {
		return ErrNotFound
	}
	delegation, ok := s.delegations[tenantID][delegationID]
	if !ok {
		return ErrNotFound
	}
	if len(delegation.Approvals) < tenant.Threshold {
		return ErrThresholdNotMet
	}
	if now.Before(delegation.NotBefore) || !now.Before(delegation.ExpiresAt) {
		return ErrDelegationInvalid
	}
	for id, current := range s.delegations[tenantID] {
		if current.State == "active" {
			current.State = "superseded"
			s.delegations[tenantID][id] = current
		}
	}
	delegation.State = "active"
	s.delegations[tenantID][delegationID] = delegation
	tenant.Status = TenantActive
	s.tenants[tenantID] = tenant
	return nil
}

func (s *MemoryStore) RevokeDelegation(tenantID, delegationID string, _ time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant, ok := s.tenants[tenantID]
	if !ok {
		return ErrNotFound
	}
	delegation, ok := s.delegations[tenantID][delegationID]
	if !ok {
		return ErrNotFound
	}
	if delegation.State == "revoked" {
		return nil
	}
	wasActive := delegation.State == "active"
	delegation.State = "revoked"
	s.delegations[tenantID][delegationID] = delegation
	if wasActive {
		tenant.Status = TenantPaused
		s.tenants[tenantID] = tenant
	}
	return nil
}

func (s *MemoryStore) ActiveDelegation(tenantID string, now time.Time) (Delegation, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return Delegation{}, ErrNotFound
	}
	for _, delegation := range s.delegations[tenantID] {
		if delegation.State == "active" && !now.Before(delegation.NotBefore) && now.Before(delegation.ExpiresAt) {
			return delegation, nil
		}
	}
	return Delegation{}, ErrNotFound
}

func (s *MemoryStore) AppendAudit(tenantID string, event AuditEvent) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return ErrNotFound
	}
	if event.TenantID != "" && event.TenantID != tenantID {
		return ErrTenantScope
	}
	event.TenantID = tenantID
	s.audit[tenantID] = append(s.audit[tenantID], event)
	return nil
}

func (s *MemoryStore) Audit(tenantID string) ([]AuditEvent, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, ok := s.tenants[tenantID]; !ok {
		return nil, ErrNotFound
	}
	return append([]AuditEvent(nil), s.audit[tenantID]...), nil
}
