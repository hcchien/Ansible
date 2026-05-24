package vc

import (
	"errors"
	"sync"
)

var (
	ErrDuplicateActiveCredential  = errors.New("duplicate_active_credential")
	ErrDuplicatePersonhoodBinding = errors.New("duplicate_personhood_binding")
)

// PersonhoodBinding records the active server-side binding between irreversible
// personhood commitments and the holder credential issued from them.
type PersonhoodBinding struct {
	NationalIDHash     string
	PassportNumberHash string
	CredentialID       string
	HolderDID          string
	Status             CredentialStatus
}

// Store tracks issued credentials for duplicate detection and status queries.
type Store struct {
	mu                   sync.RWMutex
	byID                 map[string]*record // credentialID → record
	byComm               map[string]*record // legacy commitment → active record
	byNationalIDHash     map[string]*record // national ID commitment → active record
	byPassportNumberHash map[string]*record // passport number commitment → active record
}

func NewStore() *Store {
	return &Store{
		byID:                 make(map[string]*record),
		byComm:               make(map[string]*record),
		byNationalIDHash:     make(map[string]*record),
		byPassportNumberHash: make(map[string]*record),
	}
}

// CheckDuplicate returns ErrDuplicateActiveCredential if an active credential
// already exists for the given subject commitment.
func (s *Store) CheckDuplicate(comm string) error {
	s.mu.RLock()
	r, ok := s.byNationalIDHash[comm]
	if !ok {
		r, ok = s.byComm[comm]
	}
	s.mu.RUnlock()
	if ok && r.status == StatusActive {
		return ErrDuplicateActiveCredential
	}
	return nil
}

// CheckDuplicatePersonhoodBinding returns ErrDuplicatePersonhoodBinding when an
// active credential already exists for either irreversible personhood hash.
func (s *Store) CheckDuplicatePersonhoodBinding(nationalIDHash, passportNumberHash string) error {
	s.mu.RLock()
	var r *record
	var ok bool
	if nationalIDHash != "" {
		r, ok = s.byNationalIDHash[nationalIDHash]
	}
	if (!ok || r.status != StatusActive) && passportNumberHash != "" {
		r, ok = s.byPassportNumberHash[passportNumberHash]
	}
	s.mu.RUnlock()
	if ok && r.status == StatusActive {
		return ErrDuplicatePersonhoodBinding
	}
	return nil
}

func (s *Store) add(r record) {
	s.mu.Lock()
	s.byID[r.credentialID] = &r
	if r.status == StatusActive && r.commitment != "" {
		s.byComm[r.commitment] = &r
	}
	if r.status == StatusActive && r.nationalIDHash != "" {
		s.byNationalIDHash[r.nationalIDHash] = &r
	}
	if r.status == StatusActive && r.passportNumberHash != "" {
		s.byPassportNumberHash[r.passportNumberHash] = &r
	}
	s.mu.Unlock()
}

// PersonhoodBindingByNationalIDHash returns the active binding for a national
// ID commitment, when present.
func (s *Store) PersonhoodBindingByNationalIDHash(nationalIDHash string) (PersonhoodBinding, bool) {
	s.mu.RLock()
	r, ok := s.byNationalIDHash[nationalIDHash]
	s.mu.RUnlock()
	if !ok {
		return PersonhoodBinding{}, false
	}
	return PersonhoodBinding{
		NationalIDHash:     r.nationalIDHash,
		PassportNumberHash: r.passportNumberHash,
		CredentialID:       r.credentialID,
		HolderDID:          r.holderDID,
		Status:             r.status,
	}, true
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
