package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrInvalidPassportChallenge = errors.New("invalid_passport_challenge")

const (
	passportChallengeTTL   = 15 * time.Minute
	passportScope          = "elix-passport-personhood-v1"
	passportCircuitVersion = "0.20.0"
)

type PassportChallenge struct {
	ID, DID, NonceHash, Issuer, Scope, CircuitVersion string
	ExpiresAt                                         time.Time
	ConsumedAt                                        *time.Time
}

type PassportChallengeStore interface {
	PutPassportChallenge(PassportChallenge) error
	GetPassportChallenge(id string, now time.Time) (PassportChallenge, error)
	ConsumePassportChallenge(id, did, nonceHash string, now time.Time) error
}

type MemoryPassportChallengeStore struct {
	mu         sync.Mutex
	challenges map[string]PassportChallenge
}

func NewMemoryPassportChallengeStore() *MemoryPassportChallengeStore {
	return &MemoryPassportChallengeStore{challenges: make(map[string]PassportChallenge)}
}
func (s *MemoryPassportChallengeStore) PutPassportChallenge(c PassportChallenge) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.challenges[c.ID]; ok {
		return ErrInvalidPassportChallenge
	}
	s.challenges[c.ID] = c
	return nil
}
func (s *MemoryPassportChallengeStore) GetPassportChallenge(id string, now time.Time) (PassportChallenge, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.challenges[id]
	if !ok || c.ConsumedAt != nil || !now.Before(c.ExpiresAt) {
		return PassportChallenge{}, ErrInvalidPassportChallenge
	}
	return c, nil
}
func (s *MemoryPassportChallengeStore) ConsumePassportChallenge(id, did, nonceHash string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.challenges[id]
	if !ok || c.ConsumedAt != nil || c.DID != did || c.NonceHash != nonceHash || !now.Before(c.ExpiresAt) {
		return ErrInvalidPassportChallenge
	}
	c.ConsumedAt = &now
	s.challenges[id] = c
	return nil
}

type PostgresPassportChallengeStore struct{ pool *pgxpool.Pool }

func NewPostgresPassportChallengeStore(pool *pgxpool.Pool) *PostgresPassportChallengeStore {
	return &PostgresPassportChallengeStore{pool: pool}
}
func (s *PostgresPassportChallengeStore) PutPassportChallenge(c PassportChallenge) error {
	_, err := s.pool.Exec(context.Background(), `INSERT INTO passport_challenges
		(id,did,nonce_hash,issuer,scope,circuit_version,expires_at) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		c.ID, c.DID, c.NonceHash, c.Issuer, c.Scope, c.CircuitVersion, c.ExpiresAt)
	return err
}
func (s *PostgresPassportChallengeStore) GetPassportChallenge(id string, now time.Time) (PassportChallenge, error) {
	var c PassportChallenge
	err := s.pool.QueryRow(context.Background(), `SELECT id,did,nonce_hash,issuer,scope,circuit_version,expires_at,consumed_at
		FROM passport_challenges WHERE id=$1 AND consumed_at IS NULL AND expires_at>$2`, id, now).Scan(
		&c.ID, &c.DID, &c.NonceHash, &c.Issuer, &c.Scope, &c.CircuitVersion, &c.ExpiresAt, &c.ConsumedAt)
	if err != nil {
		return PassportChallenge{}, ErrInvalidPassportChallenge
	}
	return c, nil
}
func (s *PostgresPassportChallengeStore) ConsumePassportChallenge(id, did, nonceHash string, now time.Time) error {
	tag, err := s.pool.Exec(context.Background(), `UPDATE passport_challenges SET consumed_at=$4
		WHERE id=$1 AND did=$2 AND nonce_hash=$3 AND consumed_at IS NULL AND expires_at>$4`, id, did, nonceHash, now)
	if err != nil || tag.RowsAffected() != 1 {
		return ErrInvalidPassportChallenge
	}
	return nil
}

func newPassportChallenge(did, issuer string, now time.Time) (PassportChallenge, string, error) {
	idRaw, nonceRaw := make([]byte, 16), make([]byte, 32)
	if _, err := rand.Read(idRaw); err != nil {
		return PassportChallenge{}, "", err
	}
	if _, err := rand.Read(nonceRaw); err != nil {
		return PassportChallenge{}, "", err
	}
	id, nonce := base64.RawURLEncoding.EncodeToString(idRaw), base64.RawURLEncoding.EncodeToString(nonceRaw)
	return PassportChallenge{ID: id, DID: did, NonceHash: hashPassportNonce(nonce), Issuer: issuer, Scope: passportScope, CircuitVersion: passportCircuitVersion, ExpiresAt: now.Add(passportChallengeTTL)}, nonce, nil
}
func hashPassportNonce(nonce string) string {
	sum := sha256.Sum256([]byte(nonce))
	return hex.EncodeToString(sum[:])
}

var _ PassportChallengeStore = (*MemoryPassportChallengeStore)(nil)
var _ PassportChallengeStore = (*PostgresPassportChallengeStore)(nil)
