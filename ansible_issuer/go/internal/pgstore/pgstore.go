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
		`CREATE TABLE IF NOT EXISTS issuer_tenants (
			id text PRIMARY KEY, organization_did text NOT NULL UNIQUE,
			service_slug text NOT NULL UNIQUE, mode text NOT NULL DEFAULT 'hosted',
			status text NOT NULL DEFAULT 'draft', approval_threshold int NOT NULL,
			administrator_count int NOT NULL DEFAULT 1,
			policy_version bigint NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(),
			CHECK (approval_threshold > 0), CHECK (administrator_count >= approval_threshold),
			CHECK (status IN ('draft','active','paused','closed'))
		)`,
		`ALTER TABLE issuer_tenants ADD COLUMN IF NOT EXISTS administrator_count int NOT NULL DEFAULT 1`,
		`UPDATE issuer_tenants SET administrator_count=approval_threshold WHERE administrator_count < approval_threshold`,
		`CREATE TABLE IF NOT EXISTS issuer_administrators (
			tenant_id text NOT NULL REFERENCES issuer_tenants(id), admin_did text NOT NULL,
			role text NOT NULL, state text NOT NULL DEFAULT 'invited', signing_algorithm text,
			public_key_hex text, custody text,
			PRIMARY KEY (tenant_id, admin_did)
		)`,
		`ALTER TABLE issuer_administrators ADD COLUMN IF NOT EXISTS signing_algorithm text`,
		`ALTER TABLE issuer_administrators ADD COLUMN IF NOT EXISTS public_key_hex text`,
		`ALTER TABLE issuer_administrators ADD COLUMN IF NOT EXISTS custody text`,
		`CREATE TABLE IF NOT EXISTS issuer_admin_credentials (
			tenant_id text NOT NULL, admin_did text NOT NULL, credential_id bytea NOT NULL,
			cose_public_key bytea NOT NULL, sign_count bigint NOT NULL DEFAULT 0,
			transports text[] NOT NULL DEFAULT '{}', credential_json jsonb,
			created_at timestamptz NOT NULL DEFAULT now(),
			PRIMARY KEY (tenant_id, credential_id),
			FOREIGN KEY (tenant_id, admin_did) REFERENCES issuer_administrators(tenant_id, admin_did)
		)`,
		`ALTER TABLE issuer_admin_credentials ADD COLUMN IF NOT EXISTS credential_json jsonb`,
		`CREATE TABLE IF NOT EXISTS issuer_admin_challenges (
			id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			admin_did text NOT NULL, purpose text NOT NULL, challenge_hash text NOT NULL UNIQUE,
			origin text NOT NULL, rp_id text NOT NULL, expires_at timestamptz NOT NULL,
			consumed_at timestamptz, session_data jsonb, scopes text[] NOT NULL DEFAULT '{}'
		)`,
		`ALTER TABLE issuer_admin_challenges ADD COLUMN IF NOT EXISTS session_data jsonb`,
		`ALTER TABLE issuer_admin_challenges ADD COLUMN IF NOT EXISTS scopes text[] NOT NULL DEFAULT '{}'`,
		`CREATE TABLE IF NOT EXISTS issuer_admin_capabilities (
			token_hash text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			admin_did text NOT NULL, scopes text[] NOT NULL, audience text NOT NULL,
			expires_at timestamptz NOT NULL, revoked_at timestamptz
		)`,
		`CREATE TABLE IF NOT EXISTS issuer_signing_keys (
			id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			kms_key_version text NOT NULL UNIQUE, public_key bytea NOT NULL,
			algorithm text NOT NULL, protection_level text NOT NULL, state text NOT NULL,
			version bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
			UNIQUE (tenant_id, id), UNIQUE (tenant_id, version), CHECK (protection_level IN ('HSM','HSM_SINGLE_TENANT'))
		)`,
		`CREATE TABLE IF NOT EXISTS issuer_key_delegations (
			id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			signing_key_id text NOT NULL, sequence bigint NOT NULL,
			canonical_payload jsonb NOT NULL, payload_hash text NOT NULL,
			root_signatures jsonb NOT NULL DEFAULT '{}', credential_types text[] NOT NULL,
			not_before timestamptz NOT NULL, expires_at timestamptz NOT NULL, state text NOT NULL,
			UNIQUE (tenant_id, sequence), UNIQUE (tenant_id, payload_hash),
			FOREIGN KEY (tenant_id, signing_key_id) REFERENCES issuer_signing_keys(tenant_id, id)
		)`,
		`CREATE TABLE IF NOT EXISTS credential_templates (
			id text NOT NULL, tenant_id text NOT NULL REFERENCES issuer_tenants(id), version bigint NOT NULL,
			credential_type text NOT NULL, claim_allowlist text[] NOT NULL,
			approval_threshold int NOT NULL, max_ttl_days int NOT NULL,
			policy jsonb NOT NULL, active boolean NOT NULL DEFAULT false,
			PRIMARY KEY (tenant_id, id, version), CHECK (approval_threshold > 0), CHECK (max_ttl_days > 0)
		)`,
		`CREATE TABLE IF NOT EXISTS issuance_requests (
			id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			template_id text NOT NULL, template_version bigint NOT NULL,
			applicant_pairwise_did text NOT NULL, applicant_hash text NOT NULL,
			payload_hash text NOT NULL, state text NOT NULL, policy_snapshot jsonb NOT NULL,
			expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
			UNIQUE (tenant_id, id), UNIQUE (tenant_id, payload_hash),
			FOREIGN KEY (tenant_id, template_id, template_version) REFERENCES credential_templates(tenant_id, id, version)
		)`,
		`CREATE TABLE IF NOT EXISTS issuance_approvals (
			tenant_id text NOT NULL, request_id text NOT NULL,
			approver_did text NOT NULL, decision text NOT NULL, signed_intent_hash text NOT NULL,
			created_at timestamptz NOT NULL DEFAULT now(),
			PRIMARY KEY (tenant_id, request_id, approver_did), CHECK (decision IN ('approve','deny')),
			FOREIGN KEY (tenant_id, request_id) REFERENCES issuance_requests(tenant_id, id)
		)`,
		`CREATE TABLE IF NOT EXISTS credential_records (
			credential_id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			credential_hash text NOT NULL, credential_type text NOT NULL,
			subject_pairwise_hash text NOT NULL, issued_at timestamptz NOT NULL,
			expires_at timestamptz NOT NULL, status_index bigint NOT NULL,
			status text NOT NULL DEFAULT 'active', policy_snapshot_hash text NOT NULL,
			UNIQUE (tenant_id, credential_hash), UNIQUE (tenant_id, status_index)
		)`,
		`CREATE TABLE IF NOT EXISTS issuer_status_index_reservations (
			tenant_id text NOT NULL REFERENCES issuer_tenants(id), status_index bigint NOT NULL,
			reserved_at timestamptz NOT NULL DEFAULT now(),
			PRIMARY KEY (tenant_id, status_index), CHECK (status_index >= 0)
		)`,
		`CREATE TABLE IF NOT EXISTS issuer_status_lists (
			tenant_id text NOT NULL REFERENCES issuer_tenants(id), list_version bigint NOT NULL,
			purpose text NOT NULL, published_uri text NOT NULL, encoded_list text NOT NULL,
			kms_signature_metadata jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
			PRIMARY KEY (tenant_id, list_version, purpose)
		)`,
		`CREATE TABLE IF NOT EXISTS issuer_audit_events (
			id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			event_type text NOT NULL, actor_did text, request_hash text NOT NULL,
			policy_version bigint NOT NULL, metadata jsonb NOT NULL DEFAULT '{}',
			created_at timestamptz NOT NULL DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS issuer_audit_events_tenant_time
			ON issuer_audit_events (tenant_id, created_at, id)`,
		`CREATE OR REPLACE FUNCTION reject_issuer_audit_mutation() RETURNS trigger AS $$
			BEGIN RAISE EXCEPTION 'issuer_audit_events is append-only'; END;
		$$ LANGUAGE plpgsql`,
		`DROP TRIGGER IF EXISTS issuer_audit_events_append_only ON issuer_audit_events`,
		`CREATE TRIGGER issuer_audit_events_append_only BEFORE UPDATE OR DELETE ON issuer_audit_events
			FOR EACH ROW EXECUTE FUNCTION reject_issuer_audit_mutation()`,
		`CREATE TABLE IF NOT EXISTS issuer_automation_delegations (
			id text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			source_adapter text NOT NULL, template_id text NOT NULL, template_version bigint NOT NULL,
			public_key bytea NOT NULL, rate_limit int NOT NULL, expires_at timestamptz NOT NULL,
			sequence bigint NOT NULL, state text NOT NULL,
			UNIQUE (tenant_id, sequence),
			FOREIGN KEY (tenant_id, template_id, template_version) REFERENCES credential_templates(tenant_id, id, version)
		)`,
		`CREATE TABLE IF NOT EXISTS oid4vci_grants (
			code_hash text PRIMARY KEY, tenant_id text NOT NULL REFERENCES issuer_tenants(id),
			credential_configuration_id text NOT NULL, subject_pairwise_hash text NOT NULL,
			subject_pairwise_did text NOT NULL DEFAULT '',
			expires_at timestamptz NOT NULL, consumed_at timestamptz
		)`,
		`ALTER TABLE oid4vci_grants ADD COLUMN IF NOT EXISTS subject_pairwise_did text NOT NULL DEFAULT ''`,
		`ALTER TABLE oid4vci_grants ADD COLUMN IF NOT EXISTS membership_class text NOT NULL DEFAULT 'member'`,
		`ALTER TABLE oid4vci_grants ADD COLUMN IF NOT EXISTS board_id text NOT NULL DEFAULT ''`,
		`CREATE TABLE IF NOT EXISTS oid4vci_access_tokens (
			token_hash text PRIMARY KEY, grant_code_hash text NOT NULL REFERENCES oid4vci_grants(code_hash),
			tenant_id text NOT NULL REFERENCES issuer_tenants(id), credential_configuration_id text NOT NULL,
			subject_pairwise_hash text NOT NULL, expires_at timestamptz NOT NULL, consumed_at timestamptz
		)`,
		`ALTER TABLE oid4vci_access_tokens ADD COLUMN IF NOT EXISTS subject_pairwise_did text NOT NULL DEFAULT ''`,
		`ALTER TABLE oid4vci_access_tokens ADD COLUMN IF NOT EXISTS membership_class text NOT NULL DEFAULT 'member'`,
		`ALTER TABLE oid4vci_access_tokens ADD COLUMN IF NOT EXISTS board_id text NOT NULL DEFAULT ''`,
		`ALTER TABLE oid4vci_access_tokens ADD COLUMN IF NOT EXISTS issued_at timestamptz`,
		`ALTER TABLE oid4vci_access_tokens ADD COLUMN IF NOT EXISTS status_index bigint`,
		`CREATE INDEX IF NOT EXISTS oid4vci_access_tokens_tenant_expiry
			ON oid4vci_access_tokens (tenant_id, expires_at)`,
		`CREATE TABLE IF NOT EXISTS oid4vci_nonces (
			nonce_hash text PRIMARY KEY, expires_at timestamptz NOT NULL, consumed_at timestamptz
		)`,
	}

	// Serialize schema creation across concurrent callers: `IF NOT EXISTS`
	// does NOT protect two connections racing the same CREATE (they collide
	// on pg_type/pg_class catalog inserts — SQLSTATE 23505 on
	// pg_type_typname_nsp_index). That race is real both in tests (packages
	// run in parallel against one database) and in production (this issuer
	// is built to boot as multiple horizontally-scaled instances). A
	// transaction-scoped advisory lock makes exactly one creator win; the
	// rest wait and then no-op through IF NOT EXISTS.
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("ensure issuer schema: begin: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after commit

	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock($1)", schemaLockKey); err != nil {
		return fmt.Errorf("ensure issuer schema: lock: %w", err)
	}

	for _, stmt := range stmts {
		if _, err := tx.Exec(ctx, stmt); err != nil {
			return fmt.Errorf("ensure issuer schema: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("ensure issuer schema: commit: %w", err)
	}
	return nil
}

// Arbitrary but stable advisory-lock key for issuer schema DDL ("elixissr"
// as an int64) — must only be distinct from other advisory locks on the
// same database.
const schemaLockKey int64 = 0x656C69786973_7372
