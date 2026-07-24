package oid4vci

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"sync"
	"time"
)

var (
	ErrInvalidGrant = errors.New("invalid_grant")
	ErrInvalidToken = errors.New("invalid_token")
	ErrInvalidNonce = errors.New("invalid_nonce")
)

type Grant struct {
	CodeHash                  string
	TenantID                  string
	CredentialConfigurationID string
	SubjectPairwiseHash       string
	SubjectPairwiseDID        string
	MembershipClass           string
	ForumHostID               string
	BoardID                   string
	ExpiresAt                 time.Time
	ConsumedAt                *time.Time
}

type Access struct {
	TokenHash                 string
	TenantID                  string
	CredentialConfigurationID string
	SubjectPairwiseHash       string
	SubjectPairwiseDID        string
	MembershipClass           string
	ForumHostID               string
	BoardID                   string
	IssuedAt                  *time.Time
	StatusIndex               *int64
	ExpiresAt                 time.Time
	ConsumedAt                *time.Time
}

type Nonce struct {
	Hash       string
	ExpiresAt  time.Time
	ConsumedAt *time.Time
}

type StateStore interface {
	PutGrant(Grant) error
	ExchangeGrant(codeHash, expectedTenant, tokenHash string, tokenExpiry, now time.Time) (Access, error)
	AccessByHash(tokenHash string, now time.Time) (Access, error)
	ConsumeAccess(tokenHash string, now time.Time) error
	PrepareAccess(tokenHash string, statusIndex int64, issuedAt, now time.Time) (Access, error)
	PutNonce(Nonce) error
	ConsumeNonce(hash string, now time.Time) error
}

type StateService struct {
	store StateStore
	now   func() time.Time
}

func NewStateService(store StateStore, now func() time.Time) *StateService {
	if now == nil {
		now = time.Now
	}
	return &StateService{store: store, now: now}
}

func (s *StateService) CreatePreAuthorizedGrant(tenantID, configurationID, subjectPairwiseDID, membershipClass string) (string, Grant, error) {
	return s.CreateBoardPreAuthorizedGrant(tenantID, configurationID, subjectPairwiseDID, membershipClass, "", "")
}

func (s *StateService) CreateBoardPreAuthorizedGrant(tenantID, configurationID, subjectPairwiseDID, membershipClass, forumHostID, boardID string) (string, Grant, error) {
	if tenantID == "" || configurationID == "" || subjectPairwiseDID == "" {
		return "", Grant{}, ErrInvalidGrant
	}
	if membershipClass != "member" && membershipClass != "moderator" {
		return "", Grant{}, ErrInvalidGrant
	}
	code, err := randomOpaque("eix_offer_v1_")
	if err != nil {
		return "", Grant{}, err
	}
	grant := Grant{CodeHash: hashOpaque(code), TenantID: tenantID, CredentialConfigurationID: configurationID, SubjectPairwiseHash: hashOpaque(subjectPairwiseDID), SubjectPairwiseDID: subjectPairwiseDID, MembershipClass: membershipClass, ForumHostID: forumHostID, BoardID: boardID, ExpiresAt: s.now().Add(10 * time.Minute)}
	if err := s.store.PutGrant(grant); err != nil {
		return "", Grant{}, err
	}
	return code, grant, nil
}

func (s *StateService) ExchangePreAuthorizedCode(code, expectedTenant string) (string, Access, error) {
	if len(code) < len("eix_offer_v1_")+32 {
		return "", Access{}, ErrInvalidGrant
	}
	token, err := randomOpaque("eix_credential_v1_")
	if err != nil {
		return "", Access{}, err
	}
	access, err := s.store.ExchangeGrant(hashOpaque(code), expectedTenant, hashOpaque(token), s.now().Add(5*time.Minute), s.now())
	if err != nil {
		return "", Access{}, err
	}
	return token, access, nil
}

func (s *StateService) IssueNonce() (string, error) {
	nonce, err := randomOpaque("")
	if err != nil {
		return "", err
	}
	return nonce, s.store.PutNonce(Nonce{Hash: hashOpaque(nonce), ExpiresAt: s.now().Add(2 * time.Minute)})
}

func (s *StateService) AuthorizeCredential(token, nonce string) (Access, error) {
	access, err := s.Access(token)
	if err != nil {
		return Access{}, ErrInvalidToken
	}
	if err := s.ConsumeNonce(nonce); err != nil {
		return Access{}, ErrInvalidNonce
	}
	return access, nil
}

func (s *StateService) Access(token string) (Access, error) {
	access, err := s.store.AccessByHash(hashOpaque(token), s.now())
	if err != nil {
		return Access{}, ErrInvalidToken
	}
	return access, nil
}

func (s *StateService) ConsumeNonce(nonce string) error {
	if err := s.store.ConsumeNonce(hashOpaque(nonce), s.now()); err != nil {
		return ErrInvalidNonce
	}
	return nil
}

func (s *StateService) MarkCredentialIssued(token string) error {
	return s.store.ConsumeAccess(hashOpaque(token), s.now())
}

func (s *StateService) PrepareCredential(token string, statusIndex int64, issuedAt time.Time) (Access, error) {
	return s.store.PrepareAccess(hashOpaque(token), statusIndex, issuedAt.UTC(), s.now())
}

func randomOpaque(prefix string) (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return prefix + base64.RawURLEncoding.EncodeToString(raw), nil
}

func hashOpaque(value string) string {
	digest := sha256.Sum256([]byte(value))
	return hex.EncodeToString(digest[:])
}

type MemoryStateStore struct {
	mu     sync.Mutex
	grants map[string]Grant
	access map[string]Access
	nonces map[string]Nonce
}

func NewMemoryStateStore() *MemoryStateStore {
	return &MemoryStateStore{grants: make(map[string]Grant), access: make(map[string]Access), nonces: make(map[string]Nonce)}
}

func (s *MemoryStateStore) PutGrant(grant Grant) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.grants[grant.CodeHash]; exists {
		return ErrInvalidGrant
	}
	s.grants[grant.CodeHash] = grant
	return nil
}

func (s *MemoryStateStore) ExchangeGrant(codeHash, expectedTenant, tokenHash string, tokenExpiry, now time.Time) (Access, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	grant, ok := s.grants[codeHash]
	if !ok || grant.TenantID != expectedTenant || grant.ConsumedAt != nil || !now.Before(grant.ExpiresAt) {
		return Access{}, ErrInvalidGrant
	}
	grant.ConsumedAt = &now
	s.grants[codeHash] = grant
	access := Access{TokenHash: tokenHash, TenantID: grant.TenantID, CredentialConfigurationID: grant.CredentialConfigurationID, SubjectPairwiseHash: grant.SubjectPairwiseHash, SubjectPairwiseDID: grant.SubjectPairwiseDID, MembershipClass: grant.MembershipClass, BoardID: grant.BoardID, ExpiresAt: tokenExpiry}
	s.access[tokenHash] = access
	return access, nil
}

func (s *MemoryStateStore) AccessByHash(tokenHash string, now time.Time) (Access, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	access, ok := s.access[tokenHash]
	if !ok || !now.Before(access.ExpiresAt) {
		return Access{}, ErrInvalidToken
	}
	return access, nil
}

func (s *MemoryStateStore) PrepareAccess(tokenHash string, statusIndex int64, issuedAt, now time.Time) (Access, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	access, ok := s.access[tokenHash]
	if !ok || !now.Before(access.ExpiresAt) {
		return Access{}, ErrInvalidToken
	}
	if access.StatusIndex == nil {
		access.StatusIndex = &statusIndex
		access.IssuedAt = &issuedAt
		s.access[tokenHash] = access
	}
	return access, nil
}

func (s *MemoryStateStore) ConsumeAccess(tokenHash string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	access, ok := s.access[tokenHash]
	if !ok || !now.Before(access.ExpiresAt) {
		return ErrInvalidToken
	}
	if access.ConsumedAt == nil {
		access.ConsumedAt = &now
	}
	s.access[tokenHash] = access
	return nil
}

func (s *MemoryStateStore) PutNonce(nonce Nonce) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.nonces[nonce.Hash] = nonce
	return nil
}

func (s *MemoryStateStore) ConsumeNonce(hash string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	nonce, ok := s.nonces[hash]
	if !ok || nonce.ConsumedAt != nil || !now.Before(nonce.ExpiresAt) {
		return ErrInvalidNonce
	}
	nonce.ConsumedAt = &now
	s.nonces[hash] = nonce
	return nil
}
