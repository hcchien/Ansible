package oid4vci

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresStateStore struct{ pool *pgxpool.Pool }

func NewPostgresStateStore(pool *pgxpool.Pool) *PostgresStateStore {
	return &PostgresStateStore{pool: pool}
}

func (s *PostgresStateStore) PutGrant(grant Grant) error {
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO oid4vci_grants
			(code_hash, tenant_id, credential_configuration_id, subject_pairwise_hash, subject_pairwise_did, membership_class, board_id, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, grant.CodeHash, grant.TenantID,
		grant.CredentialConfigurationID, grant.SubjectPairwiseHash, grant.SubjectPairwiseDID, grant.MembershipClass, grant.BoardID, grant.ExpiresAt)
	if uniqueViolation(err) {
		return ErrInvalidGrant
	}
	return err
}

func (s *PostgresStateStore) ExchangeGrant(codeHash, expectedTenant, tokenHash string, tokenExpiry, now time.Time) (Access, error) {
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return Access{}, err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	var grant Grant
	err = tx.QueryRow(context.Background(), `
		SELECT code_hash, tenant_id, credential_configuration_id, subject_pairwise_hash, subject_pairwise_did, membership_class, board_id, expires_at, consumed_at
		FROM oid4vci_grants
		WHERE code_hash=$1 AND tenant_id=$2 AND consumed_at IS NULL AND expires_at > $3 FOR UPDATE`, codeHash, expectedTenant, now).Scan(
		&grant.CodeHash, &grant.TenantID, &grant.CredentialConfigurationID,
		&grant.SubjectPairwiseHash, &grant.SubjectPairwiseDID, &grant.MembershipClass, &grant.BoardID, &grant.ExpiresAt, &grant.ConsumedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Access{}, ErrInvalidGrant
	}
	if err != nil {
		return Access{}, err
	}
	if _, err := tx.Exec(context.Background(), `UPDATE oid4vci_grants SET consumed_at=$2 WHERE code_hash=$1`, codeHash, now); err != nil {
		return Access{}, err
	}
	access := Access{TokenHash: tokenHash, TenantID: grant.TenantID, CredentialConfigurationID: grant.CredentialConfigurationID, SubjectPairwiseHash: grant.SubjectPairwiseHash, SubjectPairwiseDID: grant.SubjectPairwiseDID, MembershipClass: grant.MembershipClass, BoardID: grant.BoardID, ExpiresAt: tokenExpiry}
	if _, err := tx.Exec(context.Background(), `
		INSERT INTO oid4vci_access_tokens
			(token_hash, grant_code_hash, tenant_id, credential_configuration_id, subject_pairwise_hash, subject_pairwise_did, membership_class, board_id, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`, access.TokenHash, grant.CodeHash, access.TenantID,
		access.CredentialConfigurationID, access.SubjectPairwiseHash, access.SubjectPairwiseDID, access.MembershipClass, access.BoardID, access.ExpiresAt); err != nil {
		return Access{}, err
	}
	if err := tx.Commit(context.Background()); err != nil {
		return Access{}, err
	}
	return access, nil
}

func (s *PostgresStateStore) AccessByHash(tokenHash string, now time.Time) (Access, error) {
	var access Access
	err := s.pool.QueryRow(context.Background(), `
		SELECT token_hash, tenant_id, credential_configuration_id, subject_pairwise_hash, subject_pairwise_did, membership_class, board_id, issued_at, status_index, expires_at, consumed_at
		FROM oid4vci_access_tokens
		WHERE token_hash=$1 AND expires_at > $2`, tokenHash, now).Scan(
		&access.TokenHash, &access.TenantID, &access.CredentialConfigurationID,
		&access.SubjectPairwiseHash, &access.SubjectPairwiseDID, &access.MembershipClass, &access.BoardID, &access.IssuedAt, &access.StatusIndex, &access.ExpiresAt, &access.ConsumedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Access{}, ErrInvalidToken
	}
	return access, err
}

func (s *PostgresStateStore) PrepareAccess(tokenHash string, statusIndex int64, issuedAt, now time.Time) (Access, error) {
	command, err := s.pool.Exec(context.Background(), `
		UPDATE oid4vci_access_tokens
		SET status_index=COALESCE(status_index,$2), issued_at=COALESCE(issued_at,$3)
		WHERE token_hash=$1 AND expires_at > $4`, tokenHash, statusIndex, issuedAt, now)
	if err != nil {
		return Access{}, err
	}
	if command.RowsAffected() != 1 {
		return Access{}, ErrInvalidToken
	}
	return s.AccessByHash(tokenHash, now)
}

func (s *PostgresStateStore) ConsumeAccess(tokenHash string, now time.Time) error {
	command, err := s.pool.Exec(context.Background(), `
		UPDATE oid4vci_access_tokens SET consumed_at=COALESCE(consumed_at,$2)
		WHERE token_hash=$1 AND expires_at > $2`, tokenHash, now)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrInvalidToken
	}
	return nil
}

func (s *PostgresStateStore) PutNonce(nonce Nonce) error {
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO oid4vci_nonces (nonce_hash, expires_at) VALUES ($1,$2)`, nonce.Hash, nonce.ExpiresAt)
	if uniqueViolation(err) {
		return ErrInvalidNonce
	}
	return err
}

func (s *PostgresStateStore) ConsumeNonce(hash string, now time.Time) error {
	command, err := s.pool.Exec(context.Background(), `
		UPDATE oid4vci_nonces SET consumed_at=$2
		WHERE nonce_hash=$1 AND consumed_at IS NULL AND expires_at > $2`, hash, now)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrInvalidNonce
	}
	return nil
}

func uniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

var _ StateStore = (*PostgresStateStore)(nil)
