package vc

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sync"

	"github.com/trisaura/ansible_issuer/internal/atomicfile"
)

var (
	ErrDuplicateActiveCredential  = errors.New("duplicate_active_credential")
	ErrDuplicatePersonhoodBinding = errors.New("duplicate_personhood_binding")
)

const (
	PersonhoodBindingTWNationalIDContext   = "tw_national_id_v1"
	PersonhoodBindingPassportNumberContext = "passport_number_v1"
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
	path                 string
	byID                 map[string]*record // credentialID → record
	byComm               map[string]*record // legacy commitment → active record
	byNationalIDHash     map[string]*record // national ID commitment → active record
	byPassportNumberHash map[string]*record // passport number commitment → active record
}

func NewStore() *Store {
	return newStore("")
}

func NewFileStore(path string) (*Store, error) {
	if path == "" {
		return nil, errors.New("missing personhood binding store path")
	}
	store := newStore(path)
	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func newStore(path string) *Store {
	return &Store{
		path:                 path,
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

func (s *Store) add(r record) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.indexLocked(r)
	if err := s.saveLocked(); err != nil {
		s.removeLocked(r.credentialID)
		return err
	}
	return nil
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

type storeFile struct {
	Records []storedRecord `json:"records"`
}

type storedRecord struct {
	CredentialID       string           `json:"credential_id"`
	HolderDID          string           `json:"holder_did"`
	Commitment         string           `json:"commitment,omitempty"`
	NationalIDHash     string           `json:"national_id_hash,omitempty"`
	PassportNumberHash string           `json:"passport_number_hash,omitempty"`
	Status             CredentialStatus `json:"status"`
}

func (s *Store) load() error {
	b, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read personhood binding store: %w", err)
	}
	if len(b) == 0 {
		return nil
	}

	var data storeFile
	if err := json.Unmarshal(b, &data); err != nil {
		return fmt.Errorf("decode personhood binding store: %w", err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	for _, stored := range data.Records {
		if stored.CredentialID == "" {
			return errors.New("decode personhood binding store: missing credential_id")
		}
		s.indexLocked(record{
			credentialID:       stored.CredentialID,
			holderDID:          stored.HolderDID,
			commitment:         stored.Commitment,
			nationalIDHash:     stored.NationalIDHash,
			passportNumberHash: stored.PassportNumberHash,
			status:             stored.Status,
		})
	}
	return nil
}

func (s *Store) saveLocked() error {
	if s.path == "" {
		return nil
	}

	data := storeFile{Records: make([]storedRecord, 0, len(s.byID))}
	for _, r := range s.byID {
		data.Records = append(data.Records, storedRecord{
			CredentialID:       r.credentialID,
			HolderDID:          r.holderDID,
			Commitment:         r.commitment,
			NationalIDHash:     r.nationalIDHash,
			PassportNumberHash: r.passportNumberHash,
			Status:             r.status,
		})
	}

	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("encode personhood binding store: %w", err)
	}
	if err := atomicfile.Write(s.path, b, 0o600); err != nil {
		return fmt.Errorf("persist personhood binding store: %w", err)
	}
	return nil
}

func (s *Store) indexLocked(r record) {
	rec := r
	s.byID[rec.credentialID] = &rec
	if rec.status == StatusActive && rec.commitment != "" {
		s.byComm[rec.commitment] = &rec
	}
	if rec.status == StatusActive && rec.nationalIDHash != "" {
		s.byNationalIDHash[rec.nationalIDHash] = &rec
	}
	if rec.status == StatusActive && rec.passportNumberHash != "" {
		s.byPassportNumberHash[rec.passportNumberHash] = &rec
	}
}

func (s *Store) removeLocked(credentialID string) {
	r, ok := s.byID[credentialID]
	if !ok {
		return
	}
	delete(s.byID, credentialID)
	if r.commitment != "" && s.byComm[r.commitment] == r {
		delete(s.byComm, r.commitment)
	}
	if r.nationalIDHash != "" && s.byNationalIDHash[r.nationalIDHash] == r {
		delete(s.byNationalIDHash, r.nationalIDHash)
	}
	if r.passportNumberHash != "" && s.byPassportNumberHash[r.passportNumberHash] == r {
		delete(s.byPassportNumberHash, r.passportNumberHash)
	}
}
