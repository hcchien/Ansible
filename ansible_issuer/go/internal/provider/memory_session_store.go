package provider

import (
	"errors"
	"sync"
	"time"
)

type MemorySessionStore struct {
	mu               sync.Mutex
	now              func() time.Time
	authSessions     map[string]AuthSession
	verifiedSessions map[string]VerifiedSession
	replayIDs        map[string]time.Time
}

func NewMemorySessionStore(now func() time.Time) *MemorySessionStore {
	if now == nil {
		now = time.Now
	}
	return &MemorySessionStore{
		now:              now,
		authSessions:     make(map[string]AuthSession),
		verifiedSessions: make(map[string]VerifiedSession),
		replayIDs:        make(map[string]time.Time),
	}
}

func (s *MemorySessionStore) CreateAuthSession(session AuthSession) error {
	if session.OfferID == "" || session.State == "" || session.DID == "" || session.Email == "" {
		return errors.New("missing auth session field")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.authSessions[session.State] = session
	return nil
}

func (s *MemorySessionStore) ConsumeAuthState(state, replayID string) (AuthSession, error) {
	if replayID == "" {
		replayID = state
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	if replayID != "" {
		if expiresAt, seen := s.replayIDs[replayID]; seen && expiresAt.After(now) {
			return AuthSession{}, ErrReplay
		}
	}

	session, ok := s.authSessions[state]
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
	s.authSessions[state] = session
	if replayID != "" {
		s.replayIDs[replayID] = session.ExpiresAt
	}
	return session, nil
}

func (s *MemorySessionStore) MarkReplayIDConsumed(replayID string, expiresAt time.Time) error {
	if replayID == "" {
		return errors.New("missing replay id")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if seenExpiresAt, seen := s.replayIDs[replayID]; seen && seenExpiresAt.After(s.now()) {
		return ErrReplay
	}
	s.replayIDs[replayID] = expiresAt
	return nil
}

func (s *MemorySessionStore) StoreVerifiedSession(session VerifiedSession) error {
	if session.OfferID == "" || session.DID == "" || session.Email == "" || session.SubjectCommitment == "" {
		return errors.New("missing verified session field")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.verifiedSessions[session.OfferID] = session
	return nil
}

func (s *MemorySessionStore) GetVerifiedSession(offerID string) (VerifiedSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.getVerifiedSessionLocked(offerID)
}

func (s *MemorySessionStore) ConsumeVerifiedSession(offerID string) (VerifiedSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, err := s.getVerifiedSessionLocked(offerID)
	if err != nil {
		return VerifiedSession{}, err
	}
	session.Consumed = true
	s.verifiedSessions[offerID] = session
	return session, nil
}

func (s *MemorySessionStore) GetAuthSessionByOfferID(offerID string) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, session := range s.authSessions {
		if session.OfferID == offerID {
			if !session.ExpiresAt.After(s.now()) {
				return AuthSession{}, ErrExpiredSessionState
			}
			return session, nil
		}
	}
	return AuthSession{}, ErrStateNotFound
}

func (s *MemorySessionStore) CleanupExpired(retention time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	for state, session := range s.authSessions {
		if expiredBeyondRetention(session.ExpiresAt, retention, now) {
			delete(s.authSessions, state)
		}
	}
	for offerID, session := range s.verifiedSessions {
		if expiredBeyondRetention(session.ExpiresAt, retention, now) {
			delete(s.verifiedSessions, offerID)
		}
	}
	for replayID, expiresAt := range s.replayIDs {
		if expiredBeyondRetention(expiresAt, retention, now) {
			delete(s.replayIDs, replayID)
		}
	}
	return nil
}

func (s *MemorySessionStore) getVerifiedSessionLocked(offerID string) (VerifiedSession, error) {
	session, ok := s.verifiedSessions[offerID]
	if !ok || session.Consumed || !session.ExpiresAt.After(s.now()) {
		return VerifiedSession{}, ErrVerifiedNotFound
	}
	return session, nil
}
