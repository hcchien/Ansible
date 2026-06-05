// Package pgstore provides the PostgreSQL connection and schema for the issuer's
// durable stores, so the issuer can run as multiple horizontally-scaled
// instances instead of being pinned to one process with local JSON files.
package pgstore

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect opens a pooled connection to the issuer database.
func Connect(ctx context.Context, url string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("connect issuer database: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping issuer database: %w", err)
	}
	return pool, nil
}

// EnsureSchema creates the issuer tables and constraints if they do not exist.
// The partial unique indexes enforce one ACTIVE (status=0) binding per
// commitment / national-id / passport hash atomically at the database, so
// duplicate-prevention holds across concurrent instances.
func EnsureSchema(ctx context.Context, pool *pgxpool.Pool) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS personhood_bindings (
			credential_id        text PRIMARY KEY,
			holder_did           text NOT NULL,
			commitment           text,
			national_id_hash     text,
			passport_number_hash text,
			status               int  NOT NULL
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS personhood_active_commitment
			ON personhood_bindings (commitment)
			WHERE status = 0 AND commitment IS NOT NULL AND commitment <> ''`,
		`CREATE UNIQUE INDEX IF NOT EXISTS personhood_active_national_id
			ON personhood_bindings (national_id_hash)
			WHERE status = 0 AND national_id_hash IS NOT NULL AND national_id_hash <> ''`,
		`CREATE UNIQUE INDEX IF NOT EXISTS personhood_active_passport
			ON personhood_bindings (passport_number_hash)
			WHERE status = 0 AND passport_number_hash IS NOT NULL AND passport_number_hash <> ''`,
		`CREATE TABLE IF NOT EXISTS provider_auth_sessions (
			namespace          text NOT NULL,
			state              text NOT NULL,
			offer_id           text NOT NULL,
			did                text NOT NULL,
			email              text,
			subject_commitment text,
			expires_at         timestamptz NOT NULL,
			consumed           boolean NOT NULL DEFAULT false,
			PRIMARY KEY (namespace, state)
		)`,
		`CREATE INDEX IF NOT EXISTS provider_auth_sessions_offer
			ON provider_auth_sessions (namespace, offer_id)`,
		`CREATE TABLE IF NOT EXISTS provider_verified_sessions (
			namespace          text NOT NULL,
			offer_id           text NOT NULL,
			did                text NOT NULL,
			email              text,
			subject_commitment text NOT NULL,
			verified_at        timestamptz NOT NULL,
			expires_at         timestamptz NOT NULL,
			consumed           boolean NOT NULL DEFAULT false,
			PRIMARY KEY (namespace, offer_id)
		)`,
		`CREATE TABLE IF NOT EXISTS provider_replay_ids (
			namespace  text NOT NULL,
			replay_id  text NOT NULL,
			expires_at timestamptz NOT NULL,
			PRIMARY KEY (namespace, replay_id)
		)`,
	}

	for _, stmt := range stmts {
		if _, err := pool.Exec(ctx, stmt); err != nil {
			return fmt.Errorf("ensure issuer schema: %w", err)
		}
	}
	return nil
}
