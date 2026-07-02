package vc

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// pgOpTimeout bounds every issuer database call. These stores are invoked from
// request handlers that do not currently thread a request-scoped context, so a
// deadline here prevents a stalled connection from pinning a goroutine (and a
// pool slot) indefinitely under database trouble.
const pgOpTimeout = 5 * time.Second

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
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	var exists bool
	err := s.pool.QueryRow(
		ctx,
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

// CheckDuplicateAny reports a duplicate if an active credential exists under any
// of the supplied commitments (used for graceful pepper rotation dual-checks).
func (s *PostgresStore) CheckDuplicateAny(commitments []string) error {
	filtered := make([]string, 0, len(commitments))
	for _, c := range commitments {
		if c != "" {
			filtered = append(filtered, c)
		}
	}
	if len(filtered) == 0 {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	var exists bool
	err := s.pool.QueryRow(
		ctx,
		`SELECT EXISTS(
			SELECT 1 FROM personhood_bindings
			WHERE status = 0 AND (commitment = ANY($1) OR national_id_hash = ANY($1))
		)`,
		filtered,
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
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	var exists bool
	err := s.pool.QueryRow(
		ctx,
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
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	_, err := s.pool.Exec(
		ctx,
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
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	var b PersonhoodBinding
	var status int
	err := s.pool.QueryRow(
		ctx,
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
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	var status int
	err := s.pool.QueryRow(
		ctx,
		`SELECT status FROM personhood_bindings WHERE credential_id = $1`,
		credentialID,
	).Scan(&status)
	if errors.Is(err, pgx.ErrNoRows) || err != nil {
		return 0, false
	}
	return CredentialStatus(status), true
}

// Revoke marks a credential as revoked. The partial unique indexes only cover
// status = 0 rows, so flipping status frees the commitment for re-enrolment.
// Returns ErrCredentialNotFound when the credential is unknown.
func (s *PostgresStore) Revoke(credentialID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), pgOpTimeout)
	defer cancel()
	tag, err := s.pool.Exec(
		ctx,
		`UPDATE personhood_bindings SET status = $1 WHERE credential_id = $2`,
		int(StatusRevoked),
		credentialID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrCredentialNotFound
	}
	return nil
}

func nullable(value string) any {
	if value == "" {
		return nil
	}
	return value
}
