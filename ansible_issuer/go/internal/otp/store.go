package otp

import (
	"crypto/rand"
	"errors"
	"sync"
	"time"
)

var (
	ErrInvalidOTP = errors.New("invalid_otp")
	ErrExpiredOTP = errors.New("expired_otp")
)

type entry struct {
	email     string
	code      string
	expiresAt time.Time
}

// Store is a concurrency-safe, single-use OTP store keyed by DID.
type Store struct {
	mu      sync.Mutex
	entries map[string]*entry
	ttl     time.Duration
}

func NewStore(ttl time.Duration) *Store {
	return &Store{entries: make(map[string]*entry), ttl: ttl}
}

// Issue generates a 6-digit numeric OTP for (did, email) and returns it.
// Any prior OTP for the same DID is replaced.
func (s *Store) Issue(did, email string) (string, error) {
	code, err := randomDigits(6)
	if err != nil {
		return "", err
	}
	s.mu.Lock()
	s.entries[did] = &entry{email: email, code: code, expiresAt: time.Now().Add(s.ttl)}
	s.mu.Unlock()
	return code, nil
}

// VerifyAndConsume checks the OTP for (did, email) and removes it on success.
func (s *Store) VerifyAndConsume(did, email, code string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	e, ok := s.entries[did]
	if !ok || e.email != email || e.code != code {
		return ErrInvalidOTP
	}
	if time.Now().After(e.expiresAt) {
		delete(s.entries, did)
		return ErrExpiredOTP
	}
	delete(s.entries, did)
	return nil
}

func randomDigits(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	digits := make([]byte, n)
	for i, v := range b {
		digits[i] = '0' + v%10
	}
	return string(digits), nil
}
