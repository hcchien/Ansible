package vc

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresStore is the durable, horizontally-scalable credential store. Active
// duplicate-prevention is enforced by partial unique indexes (see pgstore), so
// correctness holds across concurrent issuer instances.
type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

func (s *PostgresStore) CheckDuplicate(commitment string) error {
	if commitment == "" {
		return nil
	}
	var exists bool
	err := s.pool.QueryRow(
		context.Background(),
		`SELECT EXISTS(
			SELECT 1 FROM personhood_bindings
			WHERE status = 0 AND (commitment = $1 OR national_id_hash = $1)
		)`,
		commitment,
	).Scan(&exists)
	if err != nil {
		return err
	}
	if exists {
		return ErrDuplicateActiveCredential
	}
	return nil
}

func (s *PostgresStore) CheckDuplicatePersonhoodBinding(nationalIDHash, passportNumberHash string) error {
	var exists bool
	err := s.pool.QueryRow(
		context.Background(),
		`SELECT EXISTS(
			SELECT 1 FROM personhood_bindings
			WHERE status = 0 AND (
				(national_id_hash = $1 AND $1 <> '') OR
				(passport_number_hash = $2 AND $2 <> '')
			)
		)`,
		nationalIDHash, passportNumberHash,
	).Scan(&exists)
	if err != nil {
		return err
	}
	if exists {
		return ErrDuplicatePersonhoodBinding
	}
	return nil
}

func (s *PostgresStore) add(r record) error {
	_, err := s.pool.Exec(
		context.Background(),
		`INSERT INTO personhood_bindings
			(credential_id, holder_did, commitment, national_id_hash, passport_number_hash, status)
			VALUES ($1, $2, $3, $4, $5, $6)`,
		r.credentialID,
		r.holderDID,
		nullable(r.commitment),
		nullable(r.nationalIDHash),
		nullable(r.passportNumberHash),
		int(r.status),
	)

	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		// Lost the race against a concurrent active binding.
		return ErrDuplicateActiveCredential
	}
	return err
}

func (s *PostgresStore) PersonhoodBindingByNationalIDHash(nationalIDHash string) (PersonhoodBinding, bool) {
	if nationalIDHash == "" {
		return PersonhoodBinding{}, false
	}
	var b PersonhoodBinding
	var status int
	err := s.pool.QueryRow(
		context.Background(),
		`SELECT national_id_hash, passport_number_hash, credential_id, holder_did, status
			FROM personhood_bindings
			WHERE national_id_hash = $1 AND status = 0
			LIMIT 1`,
		nationalIDHash,
	).Scan(&b.NationalIDHash, &b.PassportNumberHash, &b.CredentialID, &b.HolderDID, &status)
	if err != nil {
		return PersonhoodBinding{}, false
	}
	b.Status = CredentialStatus(status)
	return b, true
}

func (s *PostgresStore) Status(credentialID string) (CredentialStatus, bool) {
	var status int
	err := s.pool.QueryRow(
		context.Background(),
		`SELECT status FROM personhood_bindings WHERE credential_id = $1`,
		credentialID,
	).Scan(&status)
	if errors.Is(err, pgx.ErrNoRows) || err != nil {
		return 0, false
	}
	return CredentialStatus(status), true
}

func nullable(value string) any {
	if value == "" {
		return nil
	}
	return value
}
