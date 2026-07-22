package hostedissuer

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net/http"
	"sync"
	"time"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
)

var ErrWebAuthnCeremony = errors.New("issuer_admin_webauthn_ceremony_invalid")

type AdminWebAuthnSession struct {
	ID        string
	TenantID  string
	AdminDID  string
	Purpose   string
	Origin    string
	RPID      string
	Data      webauthn.SessionData
	ExpiresAt time.Time
	Consumed  bool
	Scopes    []string
}

type AdminWebAuthnStore interface {
	AdminWebAuthnCredentials(tenantID, adminDID string) ([]webauthn.Credential, error)
	PutAdminWebAuthnCredential(tenantID, adminDID string, credential webauthn.Credential) error
	UpdateAdminWebAuthnCredential(tenantID, adminDID string, credential webauthn.Credential) error
	PutAdminWebAuthnSession(AdminWebAuthnSession) error
	TakeAdminWebAuthnSession(id, tenantID, adminDID, purpose string, now time.Time) (AdminWebAuthnSession, error)
}

type adminWebAuthnUser struct {
	id          []byte
	did         string
	credentials []webauthn.Credential
}

func (u adminWebAuthnUser) WebAuthnID() []byte                         { return u.id }
func (u adminWebAuthnUser) WebAuthnName() string                       { return u.did }
func (u adminWebAuthnUser) WebAuthnDisplayName() string                { return u.did }
func (u adminWebAuthnUser) WebAuthnCredentials() []webauthn.Credential { return u.credentials }

type AdminWebAuthnService struct {
	rp           *webauthn.WebAuthn
	store        AdminWebAuthnStore
	capabilities *AdminCapabilityService
	now          func() time.Time
	rpID         string
	origin       string
}

func NewAdminWebAuthnService(rpID string, origins []string, store AdminWebAuthnStore, capabilities *AdminCapabilityService, now func() time.Time) (*AdminWebAuthnService, error) {
	if store == nil || capabilities == nil || rpID == "" || len(origins) == 0 {
		return nil, ErrWebAuthnCeremony
	}
	rp, err := webauthn.New(&webauthn.Config{
		RPID: rpID, RPDisplayName: "Elix Hosted Issuer", RPOrigins: origins,
		AuthenticatorSelection: protocol.AuthenticatorSelection{
			ResidentKey:      protocol.ResidentKeyRequirementRequired,
			UserVerification: protocol.VerificationRequired,
		},
		Timeouts: webauthn.TimeoutsConfig{
			Registration: webauthn.TimeoutConfig{Enforce: true, Timeout: 2 * time.Minute, TimeoutUVD: 2 * time.Minute},
			Login:        webauthn.TimeoutConfig{Enforce: true, Timeout: 2 * time.Minute, TimeoutUVD: 2 * time.Minute},
		},
	})
	if err != nil {
		return nil, err
	}
	if now == nil {
		now = time.Now
	}
	return &AdminWebAuthnService{rp: rp, store: store, capabilities: capabilities, now: now, rpID: rpID, origin: origins[0]}, nil
}

func (s *AdminWebAuthnService) BeginRegistration(tenantID, adminDID string) (string, *protocol.CredentialCreation, error) {
	user, err := s.user(tenantID, adminDID)
	if err != nil {
		return "", nil, err
	}
	creation, session, err := s.rp.BeginRegistration(user)
	if err != nil {
		return "", nil, err
	}
	id, err := randomCeremonyID()
	if err != nil {
		return "", nil, err
	}
	if err := s.store.PutAdminWebAuthnSession(AdminWebAuthnSession{
		ID: id, TenantID: tenantID, AdminDID: adminDID, Purpose: "register",
		Origin: s.origin, RPID: s.rpID, Data: *session, ExpiresAt: session.Expires,
	}); err != nil {
		return "", nil, err
	}
	return id, creation, nil
}

func (s *AdminWebAuthnService) FinishRegistration(tenantID, adminDID, ceremonyID string, request *http.Request) error {
	session, err := s.store.TakeAdminWebAuthnSession(ceremonyID, tenantID, adminDID, "register", s.now())
	if err != nil {
		return ErrWebAuthnCeremony
	}
	user, err := s.user(tenantID, adminDID)
	if err != nil {
		return err
	}
	credential, err := s.rp.FinishRegistration(user, session.Data, request)
	if err != nil {
		return ErrWebAuthnCeremony
	}
	return s.store.PutAdminWebAuthnCredential(tenantID, adminDID, *credential)
}

func (s *AdminWebAuthnService) BeginAuthentication(tenantID, adminDID string, scopes []string) (string, *protocol.CredentialAssertion, error) {
	canonicalScopes, err := validateAdminScopes(scopes)
	if err != nil {
		return "", nil, err
	}
	user, err := s.user(tenantID, adminDID)
	if err != nil || len(user.credentials) == 0 {
		return "", nil, ErrWebAuthnCeremony
	}
	assertion, session, err := s.rp.BeginLogin(user)
	if err != nil {
		return "", nil, err
	}
	id, err := randomCeremonyID()
	if err != nil {
		return "", nil, err
	}
	if err := s.store.PutAdminWebAuthnSession(AdminWebAuthnSession{
		ID: id, TenantID: tenantID, AdminDID: adminDID, Purpose: "authenticate",
		Origin: s.origin, RPID: s.rpID, Data: *session, ExpiresAt: session.Expires, Scopes: canonicalScopes,
	}); err != nil {
		return "", nil, err
	}
	return id, assertion, nil
}

func (s *AdminWebAuthnService) FinishAuthentication(tenantID, adminDID, ceremonyID string, request *http.Request) (string, AdminCapability, error) {
	session, err := s.store.TakeAdminWebAuthnSession(ceremonyID, tenantID, adminDID, "authenticate", s.now())
	if err != nil {
		return "", AdminCapability{}, ErrWebAuthnCeremony
	}
	user, err := s.user(tenantID, adminDID)
	if err != nil {
		return "", AdminCapability{}, err
	}
	credential, err := s.rp.FinishLogin(user, session.Data, request)
	if err != nil || !credential.Flags.UserVerified {
		return "", AdminCapability{}, ErrWebAuthnCeremony
	}
	if err := s.store.UpdateAdminWebAuthnCredential(tenantID, adminDID, *credential); err != nil {
		return "", AdminCapability{}, err
	}
	return s.capabilities.Issue(tenantID, adminDID, session.Scopes, maxAdminCapabilityTTL)
}

func (s *AdminWebAuthnService) user(tenantID, adminDID string) (adminWebAuthnUser, error) {
	credentials, err := s.store.AdminWebAuthnCredentials(tenantID, adminDID)
	if err != nil {
		return adminWebAuthnUser{}, err
	}
	id := sha256.Sum256([]byte(tenantID + "\x00" + adminDID))
	return adminWebAuthnUser{id: id[:], did: adminDID, credentials: credentials}, nil
}

func randomCeremonyID() (string, error) {
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

type MemoryAdminWebAuthnStore struct {
	mu          sync.Mutex
	credentials map[string][]webauthn.Credential
	sessions    map[string]AdminWebAuthnSession
}

func NewMemoryAdminWebAuthnStore() *MemoryAdminWebAuthnStore {
	return &MemoryAdminWebAuthnStore{credentials: make(map[string][]webauthn.Credential), sessions: make(map[string]AdminWebAuthnSession)}
}

func webAuthnAdminKey(tenantID, adminDID string) string { return tenantID + "\x00" + adminDID }

func (s *MemoryAdminWebAuthnStore) AdminWebAuthnCredentials(tenantID, adminDID string) ([]webauthn.Credential, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]webauthn.Credential(nil), s.credentials[webAuthnAdminKey(tenantID, adminDID)]...), nil
}

func (s *MemoryAdminWebAuthnStore) PutAdminWebAuthnCredential(tenantID, adminDID string, credential webauthn.Credential) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := webAuthnAdminKey(tenantID, adminDID)
	for _, existing := range s.credentials[key] {
		if string(existing.ID) == string(credential.ID) {
			return ErrWebAuthnCeremony
		}
	}
	s.credentials[key] = append(s.credentials[key], credential)
	return nil
}

func (s *MemoryAdminWebAuthnStore) UpdateAdminWebAuthnCredential(tenantID, adminDID string, credential webauthn.Credential) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := webAuthnAdminKey(tenantID, adminDID)
	for i := range s.credentials[key] {
		if string(s.credentials[key][i].ID) == string(credential.ID) {
			s.credentials[key][i] = credential
			return nil
		}
	}
	return ErrNotFound
}

func (s *MemoryAdminWebAuthnStore) PutAdminWebAuthnSession(session AdminWebAuthnSession) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[session.ID] = session
	return nil
}

func (s *MemoryAdminWebAuthnStore) TakeAdminWebAuthnSession(id, tenantID, adminDID, purpose string, now time.Time) (AdminWebAuthnSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, ok := s.sessions[id]
	if !ok || session.Consumed || session.TenantID != tenantID || session.AdminDID != adminDID || session.Purpose != purpose || !now.Before(session.ExpiresAt) {
		return AdminWebAuthnSession{}, ErrWebAuthnCeremony
	}
	session.Consumed = true
	s.sessions[id] = session
	return session, nil
}
