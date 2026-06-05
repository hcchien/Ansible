package provider

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresSessionStore is a durable, horizontally-scalable SessionStore backed
// by PostgreSQL. The namespace separates distinct flows (e.g. "tw",
// "mobilemoica") in the shared tables.
type PostgresSessionStore struct {
	pool      *pgxpool.Pool
	namespace string
	now       func() time.Time
}

func NewPostgresSessionStore(pool *pgxpool.Pool, namespace string, now func() time.Time) *PostgresSessionStore {
	if now == nil {
		now = time.Now
	}
	return &PostgresSessionStore{pool: pool, namespace: namespace, now: now}
}

func (s *PostgresSessionStore) CreateAuthSession(session AuthSession) error {
	if session.OfferID == "" || session.State == "" || session.DID == "" {
		return errors.New("missing auth session field")
	}
	_, err := s.pool.Exec(
		context.Background(),
		`INSERT INTO provider_auth_sessions
			(namespace, state, offer_id, did, email, subject_commitment, expires_at, consumed)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
			ON CONFLICT (namespace, state) DO UPDATE SET
				offer_id = EXCLUDED.offer_id, did = EXCLUDED.did, email = EXCLUDED.email,
				subject_commitment = EXCLUDED.subject_commitment, expires_at = EXCLUDED.expires_at,
				consumed = EXCLUDED.consumed`,
		s.namespace, session.State, session.OfferID, session.DID, nullable(session.Email),
		nullable(session.SubjectCommitment), session.ExpiresAt, session.Consumed,
	)
	return err
}

func (s *PostgresSessionStore) ConsumeAuthState(state, replayID string) (AuthSession, error) {
	if replayID == "" {
		replayID = state
	}
	now := s.now()

	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return AuthSession{}, err
	}
	defer tx.Rollback(context.Background())

	if replayID != "" {
		var replayExpires time.Time
		err := tx.QueryRow(context.Background(),
			`SELECT expires_at FROM provider_replay_ids WHERE namespace=$1 AND replay_id=$2`,
			s.namespace, replayID).Scan(&replayExpires)
		if err == nil && replayExpires.After(now) {
			return AuthSession{}, ErrReplay
		} else if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return AuthSession{}, err
		}
	}

	var sess AuthSession
	var email, commitment *string
	err = tx.QueryRow(context.Background(),
		`SELECT offer_id, did, email, state, subject_commitment, expires_at, consumed
			FROM provider_auth_sessions WHERE namespace=$1 AND state=$2`,
		s.namespace, state).Scan(
		&sess.OfferID, &sess.DID, &email, &sess.State, &commitment, &sess.ExpiresAt, &sess.Consumed)
	if errors.Is(err, pgx.ErrNoRows) {
		return AuthSession{}, ErrStateNotFound
	} else if err != nil {
		return AuthSession{}, err
	}
	sess.Email = deref(email)
	sess.SubjectCommitment = deref(commitment)

	if sess.Consumed {
		return AuthSession{}, ErrReplay
	}
	if !sess.ExpiresAt.After(now) {
		return AuthSession{}, ErrExpiredSessionState
	}

	if _, err := tx.Exec(context.Background(),
		`UPDATE provider_auth_sessions SET consumed=true WHERE namespace=$1 AND state=$2`,
		s.namespace, state); err != nil {
		return AuthSession{}, err
	}

	if replayID != "" {
		if _, err := tx.Exec(context.Background(),
			`INSERT INTO provider_replay_ids (namespace, replay_id, expires_at) VALUES ($1,$2,$3)
				ON CONFLICT (namespace, replay_id) DO UPDATE SET expires_at = EXCLUDED.expires_at`,
			s.namespace, replayID, sess.ExpiresAt); err != nil {
			return AuthSession{}, err
		}
	}

	if err := tx.Commit(context.Background()); err != nil {
		return AuthSession{}, err
	}
	sess.Consumed = true
	return sess, nil
}

func (s *PostgresSessionStore) MarkReplayIDConsumed(replayID string, expiresAt time.Time) error {
	if replayID == "" {
		return errors.New("missing replay id")
	}
	now := s.now()
	var existing time.Time
	err := s.pool.QueryRow(context.Background(),
		`SELECT expires_at FROM provider_replay_ids WHERE namespace=$1 AND replay_id=$2`,
		s.namespace, replayID).Scan(&existing)
	if err == nil && existing.After(now) {
		return ErrReplay
	} else if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	_, err = s.pool.Exec(context.Background(),
		`INSERT INTO provider_replay_ids (namespace, replay_id, expires_at) VALUES ($1,$2,$3)
			ON CONFLICT (namespace, replay_id) DO UPDATE SET expires_at = EXCLUDED.expires_at`,
		s.namespace, replayID, expiresAt)
	return err
}

func (s *PostgresSessionStore) StoreVerifiedSession(session VerifiedSession) error {
	if session.OfferID == "" || session.DID == "" || session.SubjectCommitment == "" {
		return errors.New("missing verified session field")
	}
	_, err := s.pool.Exec(context.Background(),
		`INSERT INTO provider_verified_sessions
			(namespace, offer_id, did, email, subject_commitment, verified_at, expires_at, consumed)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
			ON CONFLICT (namespace, offer_id) DO UPDATE SET
				did = EXCLUDED.did, email = EXCLUDED.email, subject_commitment = EXCLUDED.subject_commitment,
				verified_at = EXCLUDED.verified_at, expires_at = EXCLUDED.expires_at, consumed = EXCLUDED.consumed`,
		s.namespace, session.OfferID, session.DID, nullable(session.Email),
		session.SubjectCommitment, session.VerifiedAt, session.ExpiresAt, session.Consumed)
	return err
}

func (s *PostgresSessionStore) GetVerifiedSession(offerID string) (VerifiedSession, error) {
	sess, err := s.getVerified(s.pool, offerID)
	if err != nil {
		return VerifiedSession{}, err
	}
	return sess, nil
}

func (s *PostgresSessionStore) GetAuthSessionByOfferID(offerID string) (AuthSession, error) {
	var sess AuthSession
	var email, commitment *string
	err := s.pool.QueryRow(context.Background(),
		`SELECT offer_id, did, email, state, subject_commitment, expires_at, consumed
			FROM provider_auth_sessions WHERE namespace=$1 AND offer_id=$2 LIMIT 1`,
		s.namespace, offerID).Scan(
		&sess.OfferID, &sess.DID, &email, &sess.State, &commitment, &sess.ExpiresAt, &sess.Consumed)
	if errors.Is(err, pgx.ErrNoRows) {
		return AuthSession{}, ErrStateNotFound
	} else if err != nil {
		return AuthSession{}, err
	}
	if !sess.ExpiresAt.After(s.now()) {
		return AuthSession{}, ErrExpiredSessionState
	}
	sess.Email = deref(email)
	sess.SubjectCommitment = deref(commitment)
	return sess, nil
}

func (s *PostgresSessionStore) ConsumeVerifiedSession(offerID string) (VerifiedSession, error) {
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return VerifiedSession{}, err
	}
	defer tx.Rollback(context.Background())

	sess, err := s.getVerified(tx, offerID)
	if err != nil {
		return VerifiedSession{}, err
	}
	if _, err := tx.Exec(context.Background(),
		`UPDATE provider_verified_sessions SET consumed=true WHERE namespace=$1 AND offer_id=$2`,
		s.namespace, offerID); err != nil {
		return VerifiedSession{}, err
	}
	if err := tx.Commit(context.Background()); err != nil {
		return VerifiedSession{}, err
	}
	sess.Consumed = true
	return sess, nil
}

func (s *PostgresSessionStore) CleanupExpired(retention time.Duration) error {
	if retention < 0 {
		retention = 0
	}
	cutoff := s.now().Add(-retention)
	for _, table := range []string{"provider_auth_sessions", "provider_verified_sessions", "provider_replay_ids"} {
		if _, err := s.pool.Exec(context.Background(),
			"DELETE FROM "+table+" WHERE namespace=$1 AND expires_at <= $2", s.namespace, cutoff); err != nil {
			return err
		}
	}
	return nil
}

type querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

func (s *PostgresSessionStore) getVerified(q querier, offerID string) (VerifiedSession, error) {
	var sess VerifiedSession
	var email *string
	err := q.QueryRow(context.Background(),
		`SELECT offer_id, did, email, subject_commitment, verified_at, expires_at, consumed
			FROM provider_verified_sessions WHERE namespace=$1 AND offer_id=$2`,
		s.namespace, offerID).Scan(
		&sess.OfferID, &sess.DID, &email, &sess.SubjectCommitment, &sess.VerifiedAt, &sess.ExpiresAt, &sess.Consumed)
	if errors.Is(err, pgx.ErrNoRows) {
		return VerifiedSession{}, ErrVerifiedNotFound
	} else if err != nil {
		return VerifiedSession{}, err
	}
	if sess.Consumed || !sess.ExpiresAt.After(s.now()) {
		return VerifiedSession{}, ErrVerifiedNotFound
	}
	sess.Email = deref(email)
	return sess, nil
}

func nullable(value string) any {
	if value == "" {
		return nil
	}
	return value
}

func deref(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
