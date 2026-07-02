package otp

import (
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"sync"
	"time"
)

var (
	ErrInvalidOTP      = errors.New("invalid_otp")
	ErrExpiredOTP      = errors.New("expired_otp")
	ErrTooManyAttempts = errors.New("too_many_attempts")
)

// maxVerifyAttempts bounds how many codes may be tried against a single issued
// OTP before it is destroyed. A 6-digit code has a 10^6 space, so capping at 5
// keeps the per-issue brute-force success probability negligible; obtaining
// more guesses requires a fresh Issue call, which re-notifies the email owner.
const maxVerifyAttempts = 5

type entry struct {
	email     string
	code      string
	expiresAt time.Time
	attempts  int
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
//
// Each Issue also sweeps expired entries so an attacker minting a fresh DID per
// request cannot grow the map without bound: every entry has a TTL, and stale
// ones are dropped opportunistically on the write path rather than lingering
// until a matching verify (which never comes for abandoned/attacker DIDs).
func (s *Store) Issue(did, email string) (string, error) {
	code, err := randomDigits(6)
	if err != nil {
		return "", err
	}
	now := time.Now()
	s.mu.Lock()
	s.sweepLocked(now)
	s.entries[did] = &entry{email: email, code: code, expiresAt: now.Add(s.ttl)}
	s.mu.Unlock()
	return code, nil
}

// sweepLocked deletes every expired entry. Caller must hold s.mu.
func (s *Store) sweepLocked(now time.Time) {
	for did, e := range s.entries {
		if now.After(e.expiresAt) {
			delete(s.entries, did)
		}
	}
}

// VerifyAndConsume checks the OTP for (did, email) and removes it on success.
// A wrong code counts against a per-issue attempt cap; once the cap is reached
// the entry is destroyed so an attacker cannot keep guessing a single code.
// The code and email are compared in constant time to avoid a timing oracle.
func (s *Store) VerifyAndConsume(did, email, code string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	e, ok := s.entries[did]
	if !ok {
		return ErrInvalidOTP
	}
	if time.Now().After(e.expiresAt) {
		delete(s.entries, did)
		return ErrExpiredOTP
	}

	emailOK := subtle.ConstantTimeCompare([]byte(e.email), []byte(email)) == 1
	codeOK := subtle.ConstantTimeCompare([]byte(e.code), []byte(code)) == 1
	if !emailOK || !codeOK {
		e.attempts++
		if e.attempts >= maxVerifyAttempts {
			delete(s.entries, did)
			return ErrTooManyAttempts
		}
		return ErrInvalidOTP
	}

	delete(s.entries, did)
	return nil
}

// Len returns the number of live entries. It exists mainly so tests can assert
// the map does not grow without bound.
func (s *Store) Len() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.entries)
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
