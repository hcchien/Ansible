//! Shared test fixture: a temp data dir with an `ansible.db` whose DDL
//! mirrors the drift-generated snake_case schema (subset the binary touches),
//! plus grant-file helpers.
//!
//! Keep the DDL in lockstep with `ansible_core/store/lib/src/schema/*.dart`;
//! plan risk "enum string drift" is covered by seeding real enum values
//! (outbound/accepted, murmur/note, private/unlisted/public).

use std::path::{Path, PathBuf};

use rusqlite::Connection;

pub const SCHEMA_VERSION: i64 = 35;

pub struct Fixture {
    pub dir: PathBuf,
}

// Each integration-test binary compiles this module separately, so any helper
// unused by that particular binary would warn without the allow.
#[allow(dead_code)]
impl Fixture {
    pub fn data_dir(&self) -> &Path {
        &self.dir
    }

    pub fn db_path(&self) -> PathBuf {
        self.dir.join("ansible.db")
    }

    pub fn grant_path(&self) -> PathBuf {
        self.dir.join("mcp_access_grant.json")
    }

    pub fn write_grant(&self, json: &str) {
        std::fs::write(self.grant_path(), json).unwrap();
    }

    /// A permissive, unexpired grant: all boards, murmurs + follow feed on,
    /// local author `did:key:local`.
    pub fn write_default_grant(&self) {
        self.write_grant(
            r#"{
                "grant_id": "test-grant",
                "created_at": "2026-07-01T00:00:00Z",
                "expires_at": "2999-01-01T00:00:00Z",
                "local_author_dids": ["did:key:local"],
                "scopes": {
                    "boards": "all",
                    "include_murmurs": true,
                    "include_follow_feed": true
                }
            }"#,
        );
    }

    /// Grant limited to board `b-dev`, optional scopes off.
    pub fn write_narrow_grant(&self) {
        self.write_grant(
            r#"{
                "grant_id": "narrow-grant",
                "created_at": "2026-07-01T00:00:00Z",
                "expires_at": "2999-01-01T00:00:00Z",
                "local_author_dids": ["did:key:local"],
                "scopes": {
                    "boards": ["b-dev"],
                    "include_murmurs": false,
                    "include_follow_feed": false
                }
            }"#,
        );
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn temp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "ansible_mcp_test_{tag}_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

pub fn empty_fixture(tag: &str) -> Fixture {
    Fixture { dir: temp_dir(tag) }
}

/// Full fixture: schema + seed data covering both compliance-relevant cases
/// (a second board `b-priv` outside narrow grants, another author's private
/// and local-only murmurs).
pub fn seeded_fixture(tag: &str) -> Fixture {
    let fixture = empty_fixture(tag);
    let conn = Connection::open(fixture.db_path()).unwrap();
    create_schema(&conn, SCHEMA_VERSION);
    seed(&conn);
    fixture
}

pub fn create_schema(conn: &Connection, user_version: i64) {
    conn.execute_batch(&format!(
        r#"
        PRAGMA user_version = {user_version};

        CREATE TABLE boards (
            board_id TEXT PRIMARY KEY,
            slug TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            description TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE threads (
            thread_id TEXT PRIMARY KEY,
            board_id TEXT NOT NULL REFERENCES boards (board_id),
            title TEXT NOT NULL,
            author_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE posts (
            post_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL REFERENCES threads (thread_id),
            board_id TEXT NOT NULL REFERENCES boards (board_id),
            author_id TEXT NOT NULL,
            content TEXT NOT NULL,
            parent_post_id TEXT REFERENCES posts (post_id),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_edit_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            signature_verified INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE content_items (
            content_item_id TEXT PRIMARY KEY,
            author_did TEXT NOT NULL,
            subject_id TEXT,
            mode TEXT NOT NULL,
            title TEXT,
            body TEXT NOT NULL,
            status TEXT NOT NULL,
            visibility TEXT NOT NULL,
            published_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            is_deleted INTEGER NOT NULL DEFAULT 0,
            local_only INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE follow_targets (
            target_id TEXT PRIMARY KEY,
            target_type TEXT NOT NULL,
            canonical_uri TEXT UNIQUE,
            display_name TEXT NOT NULL,
            handle TEXT,
            did TEXT,
            actor_uri TEXT,
            inbox_uri TEXT,
            outbox_uri TEXT,
            remote_node_id TEXT,
            board_id TEXT,
            board_slug TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE follow_edges (
            follow_id TEXT PRIMARY KEY,
            follower_did TEXT NOT NULL,
            target_id TEXT NOT NULL REFERENCES follow_targets (target_id),
            target_type TEXT NOT NULL,
            direction TEXT NOT NULL,
            status TEXT NOT NULL,
            visibility TEXT NOT NULL,
            remote_activity_id TEXT,
            last_error TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            accepted_at INTEGER,
            cancelled_at INTEGER
        );
        CREATE TABLE contact_records (
            subject_did TEXT PRIMARY KEY,
            handle TEXT UNIQUE,
            display_name TEXT,
            local_alias TEXT,
            avatar_url TEXT
        );
        CREATE TABLE did_reputations (
            did TEXT PRIMARY KEY,
            tier TEXT NOT NULL
        );
        CREATE TABLE forum_hosts (
            forum_host_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            base_url TEXT NOT NULL,
            canonical_host_uri TEXT NOT NULL,
            server_kind TEXT NOT NULL,
            capabilities_json TEXT NOT NULL DEFAULT '{{}}',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        );
        CREATE TABLE remote_nodes (
            node_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            access_token TEXT,
            sync_cursor INTEGER NOT NULL DEFAULT 0,
            last_sync_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            is_active INTEGER NOT NULL DEFAULT 1,
            constitution_compliance TEXT
        );
        CREATE TABLE board_subscriptions (
            subscription_id TEXT PRIMARY KEY,
            forum_host_id TEXT NOT NULL,
            hosted_board_id TEXT NOT NULL,
            local_board_id TEXT NOT NULL,
            sync_cursor INTEGER NOT NULL DEFAULT 0,
            retention_days INTEGER
        );
        CREATE TABLE board_sync_configs (
            config_id TEXT PRIMARY KEY,
            remote_node_id TEXT NOT NULL,
            board_id TEXT NOT NULL,
            retention_days INTEGER
        );
        CREATE TABLE deliberation_exports (
            export_id TEXT PRIMARY KEY,
            board_id TEXT NOT NULL,
            deliberation_id TEXT NOT NULL,
            title TEXT NOT NULL,
            view TEXT NOT NULL,
            manifest_json TEXT NOT NULL,
            report_json TEXT NOT NULL,
            statements_json TEXT,
            responses_json TEXT,
            expires_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL
        );
        "#
    ))
    .unwrap();
}

fn seed(conn: &Connection) {
    conn.execute_batch(
        r#"
        INSERT INTO boards VALUES
            ('b-dev', 'dev', 'Development', 'Dev talk', 1751500000, 1751500000, 0),
            ('b-priv', 'private-club', 'Private Club', 'Out of narrow scope', 1751500000, 1751500000, 0),
            ('b-gone', 'gone', 'Deleted Board', NULL, 1751500000, 1751500000, 1);

        INSERT INTO threads VALUES
            ('t-1', 'b-dev', 'Welcome to dev', 'did:key:alice', 1751600000, 1751700000, 0),
            ('t-2', 'b-dev', 'Rust tips', 'did:key:bob', 1751610000, 1751690000, 0),
            ('t-secret', 'b-priv', 'Secret plans', 'did:key:carol', 1751620000, 1751680000, 0);

        INSERT INTO posts VALUES
            ('p-1', 't-1', 'b-dev', 'did:key:alice', 'First post about zebras', NULL,
             1751600000, 1751600000, 1751600000, 0, 1),
            ('p-2', 't-1', 'b-dev', 'did:key:bob', 'Reply mentioning zebras too', 'p-1',
             1751601000, 1751601000, 1751601000, 0, 0),
            ('p-3', 't-2', 'b-dev', 'did:key:bob', 'Borrow checker wisdom', NULL,
             1751610000, 1751610000, 1751610000, 0, 1),
            ('p-del', 't-1', 'b-dev', 'did:key:alice', 'Deleted zebras post', NULL,
             1751602000, 1751602000, 1751602000, 1, 0),
            ('p-secret', 't-secret', 'b-priv', 'did:key:carol', 'Secret zebra cabal', NULL,
             1751620000, 1751620000, 1751620000, 0, 0);

        INSERT INTO content_items VALUES
            ('m-own-private', 'did:key:local', NULL, 'murmur', NULL,
             'My own private murmur about zebras', 'published', 'private',
             NULL, 1751630000, 1751630000, 0, 1),
            ('m-alice-public', 'did:key:alice', NULL, 'murmur', NULL,
             'Alice public murmur', 'published', 'public',
             1751640000, 1751640000, 1751640000, 0, 0),
            ('m-alice-private', 'did:key:alice', NULL, 'murmur', NULL,
             'Alice PRIVATE zebra murmur - must never leak', 'published', 'private',
             NULL, 1751650000, 1751650000, 0, 0),
            ('m-alice-localonly', 'did:key:alice', NULL, 'note', NULL,
             'Alice local-only zebra note - must never leak', 'published', 'public',
             NULL, 1751660000, 1751660000, 0, 1);

        INSERT INTO follow_targets
            (target_id, target_type, canonical_uri, display_name, handle, did,
             board_id, board_slug)
        VALUES
            ('ft-alice', 'user', NULL, 'Alice', 'alice', 'did:key:alice', NULL, NULL),
            ('ft-dev', 'board', 'local://boards/b-dev', 'Development', NULL, NULL, 'b-dev', 'dev'),
            ('ft-priv', 'board', 'local://boards/b-priv', 'Private Club', NULL, NULL, 'b-priv', 'private-club');

        INSERT INTO follow_edges VALUES
            ('f-1', 'did:key:local', 'ft-alice', 'user', 'outbound', 'accepted', 'localOnly',
             NULL, NULL, 1751500000, 1751500000, 1751500000, NULL),
            ('f-2', 'did:key:local', 'ft-dev', 'board', 'outbound', 'accepted', 'localOnly',
             NULL, NULL, 1751500000, 1751500000, 1751500000, NULL),
            ('f-3', 'did:key:local', 'ft-priv', 'board', 'outbound', 'pending', 'localOnly',
             NULL, NULL, 1751500000, 1751500000, NULL, NULL);

        INSERT INTO contact_records VALUES
            ('did:key:alice', 'alice', 'Alice A.', 'my secret nickname for alice', NULL),
            ('did:key:bob', 'bob', 'Bob B.', NULL, NULL);

        INSERT INTO did_reputations VALUES
            ('did:key:alice', 'verified_human'),
            ('did:key:bob', 'basic');

        INSERT INTO forum_hosts VALUES
            ('fh-1', 'Genesis Host', 'https://genesis.example', 'https://genesis.example',
             'trisaura', '{}', 1, 1751500000, 1751500000);

        INSERT INTO remote_nodes VALUES
            ('rn-1', 'Peer Node', 'https://peer.example', 'SECRET-TOKEN-MUST-NOT-LEAK',
             0, NULL, 1751500000, 1751500000, 1, 'compatible');

        INSERT INTO board_subscriptions VALUES
            ('sub-1', 'fh-1', 'hosted-dev', 'b-dev', 0, NULL);

        INSERT INTO board_sync_configs VALUES
            ('cfg-1', 'rn-1', 'b-priv', NULL);

        INSERT INTO deliberation_exports VALUES
            ('export-dev', 'b-dev', 'd-dev', 'How should we ship?', 'pseudonymous_matrix',
             '{"dataset_digest":"abc","algorithm":"elix-deliberation-aggregates","algorithm_version":"1.0.0","participant_identifiers":"export_scoped_pseudonyms"}',
             '{"participant_count":3,"response_count":3,"consensus":[]}',
             '[{"id":"s-1","text":"Ship weekly"}]',
             '[{"export_participant_id":"export-person-1","statement_id":"s-1","stance":"agree"}]',
             32472144000, 1751800000),
            ('export-private', 'b-priv', 'd-private', 'Secret deliberation', 'aggregates',
             '{"dataset_digest":"private"}',
             '{"participant_count":9,"response_count":18}',
             NULL, NULL, 32472144000, 1751800000);
        "#,
    )
    .unwrap();
}
