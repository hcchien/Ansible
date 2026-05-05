package vc

import (
	"errors"
	"sync"
)

var ErrDuplicateActiveCredential = errors.New("duplicate_active_credential")

// Store tracks issued credentials for duplicate detection and status queries.
type Store struct {
	mu     sync.RWMutex
	byID   map[string]*record // credentialID → record
	byComm map[string]*record // commitment → active record
}

func NewStore() *Store {
	return &Store{
		byID:   make(map[string]*record),
		byComm: make(map[string]*record),
	}
}

// CheckDuplicate returns ErrDuplicateActiveCredential if an active credential
// already exists for the given subject commitment.
func (s *Store) CheckDuplicate(comm string) error {
	s.mu.RLock()
	r, ok := s.byComm[comm]
	s.mu.RUnlock()
	if ok && r.status == StatusActive {
		return ErrDuplicateActiveCredential
	}
	return nil
}

func (s *Store) add(r record) {
	s.mu.Lock()
	s.byID[r.credentialID] = &r
	if r.status == StatusActive {
		s.byComm[r.commitment] = &r
	}
	s.mu.Unlock()
}

// Status returns the lifecycle state of a credential by ID.
func (s *Store) Status(credentialID string) (CredentialStatus, bool) {
	s.mu.RLock()
	r, ok := s.byID[credentialID]
	s.mu.RUnlock()
	if !ok {
		return 0, false
	}
	return r.status, true
}
