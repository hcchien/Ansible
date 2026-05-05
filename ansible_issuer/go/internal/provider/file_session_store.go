package provider

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type fileSessionData struct {
	AuthSessions     map[string]AuthSession     `json:"auth_sessions"`
	VerifiedSessions map[string]VerifiedSession `json:"verified_sessions"`
	ReplayIDs        map[string]time.Time       `json:"replay_ids"`
}

type FileSessionStore struct {
	mu   sync.Mutex
	path string
	now  func() time.Time
	data fileSessionData
}

func NewFileSessionStore(path string, now func() time.Time) (*FileSessionStore, error) {
	if path == "" {
		return nil, errors.New("missing session store path")
	}
	if now == nil {
		now = time.Now
	}
	store := &FileSessionStore{
		path: path,
		now:  now,
		data: newFileSessionData(),
	}
	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *FileSessionStore) CreateAuthSession(session AuthSession) error {
	if session.OfferID == "" || session.State == "" || session.DID == "" || session.Email == "" {
		return errors.New("missing auth session field")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	s.data.AuthSessions[session.State] = session
	return s.saveLocked()
}

func (s *FileSessionStore) ConsumeAuthState(state, replayID string) (AuthSession, error) {
	if replayID == "" {
		replayID = state
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	if replayID != "" {
		if expiresAt, seen := s.data.ReplayIDs[replayID]; seen && expiresAt.After(now) {
			return AuthSession{}, ErrReplay
		}
	}

	session, ok := s.data.AuthSessions[state]
	if !ok {
		return AuthSession{}, ErrStateNotFound
	}
	if session.Consumed {
		return AuthSession{}, ErrReplay
	}
	if !session.ExpiresAt.After(now) {
		return AuthSession{}, ErrExpiredSessionState
	}

	session.Consumed = true
	s.data.AuthSessions[state] = session
	if replayID != "" {
		s.data.ReplayIDs[replayID] = session.ExpiresAt
	}
	if err := s.saveLocked(); err != nil {
		return AuthSession{}, err
	}
	return session, nil
}

func (s *FileSessionStore) MarkReplayIDConsumed(replayID string, expiresAt time.Time) error {
	if replayID == "" {
		return errors.New("missing replay id")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if seenExpiresAt, seen := s.data.ReplayIDs[replayID]; seen && seenExpiresAt.After(s.now()) {
		return ErrReplay
	}
	s.data.ReplayIDs[replayID] = expiresAt
	return s.saveLocked()
}

func (s *FileSessionStore) StoreVerifiedSession(session VerifiedSession) error {
	if session.OfferID == "" || session.DID == "" || session.Email == "" || session.SubjectCommitment == "" {
		return errors.New("missing verified session field")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	s.data.VerifiedSessions[session.OfferID] = session
	return s.saveLocked()
}

func (s *FileSessionStore) GetVerifiedSession(offerID string) (VerifiedSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	return s.getVerifiedSessionLocked(offerID)
}

func (s *FileSessionStore) GetAuthSessionByOfferID(offerID string) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, session := range s.data.AuthSessions {
		if session.OfferID == offerID {
			if !session.ExpiresAt.After(s.now()) {
				return AuthSession{}, ErrExpiredSessionState
			}
			return session, nil
		}
	}
	return AuthSession{}, ErrStateNotFound
}

func (s *FileSessionStore) ConsumeVerifiedSession(offerID string) (VerifiedSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	session, err := s.getVerifiedSessionLocked(offerID)
	if err != nil {
		return VerifiedSession{}, err
	}
	session.Consumed = true
	s.data.VerifiedSessions[offerID] = session
	if err := s.saveLocked(); err != nil {
		return VerifiedSession{}, err
	}
	return session, nil
}

func (s *FileSessionStore) CleanupExpired(retention time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	for state, session := range s.data.AuthSessions {
		if expiredBeyondRetention(session.ExpiresAt, retention, now) {
			delete(s.data.AuthSessions, state)
		}
	}
	for offerID, session := range s.data.VerifiedSessions {
		if expiredBeyondRetention(session.ExpiresAt, retention, now) {
			delete(s.data.VerifiedSessions, offerID)
		}
	}
	for replayID, expiresAt := range s.data.ReplayIDs {
		if expiredBeyondRetention(expiresAt, retention, now) {
			delete(s.data.ReplayIDs, replayID)
		}
	}
	return s.saveLocked()
}

func (s *FileSessionStore) getVerifiedSessionLocked(offerID string) (VerifiedSession, error) {
	session, ok := s.data.VerifiedSessions[offerID]
	if !ok || session.Consumed || !session.ExpiresAt.After(s.now()) {
		return VerifiedSession{}, ErrVerifiedNotFound
	}
	return session, nil
}

func (s *FileSessionStore) load() error {
	b, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read session store: %w", err)
	}
	if len(b) == 0 {
		return nil
	}
	if err := json.Unmarshal(b, &s.data); err != nil {
		return fmt.Errorf("decode session store: %w", err)
	}
	s.ensureMaps()
	return nil
}

func (s *FileSessionStore) saveLocked() error {
	s.ensureMaps()
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return fmt.Errorf("create session store directory: %w", err)
	}
	b, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return fmt.Errorf("encode session store: %w", err)
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return fmt.Errorf("write session store: %w", err)
	}
	if err := os.Rename(tmp, s.path); err != nil {
		return fmt.Errorf("replace session store: %w", err)
	}
	return nil
}

func (s *FileSessionStore) ensureMaps() {
	if s.data.AuthSessions == nil {
		s.data.AuthSessions = make(map[string]AuthSession)
	}
	if s.data.VerifiedSessions == nil {
		s.data.VerifiedSessions = make(map[string]VerifiedSession)
	}
	if s.data.ReplayIDs == nil {
		s.data.ReplayIDs = make(map[string]time.Time)
	}
}

func newFileSessionData() fileSessionData {
	return fileSessionData{
		AuthSessions:     make(map[string]AuthSession),
		VerifiedSessions: make(map[string]VerifiedSession),
		ReplayIDs:        make(map[string]time.Time),
	}
}

func expiredBeyondRetention(expiresAt time.Time, retention time.Duration, now time.Time) bool {
	if retention < 0 {
		retention = 0
	}
	return !expiresAt.Add(retention).After(now)
}
