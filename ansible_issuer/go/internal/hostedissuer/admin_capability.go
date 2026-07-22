package hostedissuer

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	AdminCapabilityAudience = "issuer.elix.cool/hosted-admin"
	maxAdminCapabilityTTL   = 5 * time.Minute
)

var (
	ErrCapabilityInvalid = errors.New("issuer_admin_capability_invalid")
	ErrCapabilityScope   = errors.New("issuer_admin_capability_scope_denied")
)

type AdminCapability struct {
	TokenHash string
	TenantID  string
	AdminDID  string
	Scopes    []string
	Audience  string
	ExpiresAt time.Time
	RevokedAt *time.Time
}

type AdminCapabilityStore interface {
	PutAdminCapability(AdminCapability) error
	AdminCapabilityByHash(tokenHash string) (AdminCapability, error)
	RevokeAdminCapabilities(tenantID, adminDID string, at time.Time) error
}

type AdminCapabilityService struct {
	store AdminCapabilityStore
	now   func() time.Time
}

func NewAdminCapabilityService(store AdminCapabilityStore, now func() time.Time) *AdminCapabilityService {
	if now == nil {
		now = time.Now
	}
	return &AdminCapabilityService{store: store, now: now}
}

func (s *AdminCapabilityService) Issue(tenantID, adminDID string, scopes []string, ttl time.Duration) (string, AdminCapability, error) {
	if tenantID == "" || adminDID == "" || len(scopes) == 0 {
		return "", AdminCapability{}, ErrCapabilityInvalid
	}
	if ttl <= 0 || ttl > maxAdminCapabilityTTL {
		ttl = maxAdminCapabilityTTL
	}
	canonicalScopes, err := validateAdminScopes(scopes)
	if err != nil {
		return "", AdminCapability{}, err
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", AdminCapability{}, err
	}
	token := "eix_admin_v1_" + base64.RawURLEncoding.EncodeToString(raw)
	capability := AdminCapability{
		TokenHash: hashAdminToken(token), TenantID: tenantID, AdminDID: adminDID,
		Scopes: canonicalScopes, Audience: AdminCapabilityAudience, ExpiresAt: s.now().Add(ttl),
	}
	if err := s.store.PutAdminCapability(capability); err != nil {
		return "", AdminCapability{}, err
	}
	return token, capability, nil
}

func (s *AdminCapabilityService) Authorize(token, tenantID, requiredScope string) (AdminCapability, error) {
	if !strings.HasPrefix(token, "eix_admin_v1_") || tenantID == "" {
		return AdminCapability{}, ErrCapabilityInvalid
	}
	capability, err := s.store.AdminCapabilityByHash(hashAdminToken(token))
	if err != nil || capability.TenantID != tenantID || capability.Audience != AdminCapabilityAudience ||
		capability.RevokedAt != nil || !s.now().Before(capability.ExpiresAt) {
		return AdminCapability{}, ErrCapabilityInvalid
	}
	for _, scope := range capability.Scopes {
		if scope == requiredScope {
			return capability, nil
		}
	}
	return AdminCapability{}, ErrCapabilityScope
}

func (s *AdminCapabilityService) RevokeAdministrator(tenantID, adminDID string) error {
	return s.store.RevokeAdminCapabilities(tenantID, adminDID, s.now().UTC())
}

func validateAdminScopes(scopes []string) ([]string, error) {
	allowed := map[string]bool{
		"issuer_admin:tenant": true, "issuer_admin:keys": true,
		"issuer_admin:admins":      true,
		"issuer_admin:delegations": true, "issuer_admin:templates": true,
		"issuer_admin:issuance": true, "issuer_admin:status": true, "issuer_admin:audit": true,
	}
	seen := make(map[string]bool)
	result := make([]string, 0, len(scopes))
	for _, scope := range scopes {
		if !allowed[scope] {
			return nil, ErrCapabilityScope
		}
		if !seen[scope] {
			seen[scope] = true
			result = append(result, scope)
		}
	}
	sort.Strings(result)
	return result, nil
}

func hashAdminToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

type MemoryAdminCapabilityStore struct {
	mu     sync.RWMutex
	byHash map[string]AdminCapability
}

func NewMemoryAdminCapabilityStore() *MemoryAdminCapabilityStore {
	return &MemoryAdminCapabilityStore{byHash: make(map[string]AdminCapability)}
}

func (s *MemoryAdminCapabilityStore) PutAdminCapability(capability AdminCapability) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.byHash[capability.TokenHash] = capability
	return nil
}

func (s *MemoryAdminCapabilityStore) AdminCapabilityByHash(hash string) (AdminCapability, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	capability, ok := s.byHash[hash]
	if !ok {
		return AdminCapability{}, ErrNotFound
	}
	return capability, nil
}

func (s *MemoryAdminCapabilityStore) RevokeAdminCapabilities(tenantID, adminDID string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for hash, capability := range s.byHash {
		if capability.TenantID == tenantID && capability.AdminDID == adminDID {
			capability.RevokedAt = &at
			s.byHash[hash] = capability
		}
	}
	return nil
}
