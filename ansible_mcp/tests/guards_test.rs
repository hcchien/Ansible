//! T-106: grant parsing/expiry/revocation and DB guard chain, fail closed.

mod common;

use ansible_mcp::{db, grant};
use rusqlite::Connection;

#[test]
fn grant_missing_fails_closed() {
    let fixture = common::seeded_fixture("grant_missing");
    let err = grant::load(fixture.data_dir()).unwrap_err();
    assert!(matches!(err, grant::GrantError::Missing(_)));
    assert!(err.denial_message().contains("Access not granted"));
}

#[test]
fn grant_expired_fails_closed() {
    let fixture = common::seeded_fixture("grant_expired");
    fixture.write_grant(
        r#"{
            "grant_id": "old",
            "created_at": "2026-01-01T00:00:00Z",
            "expires_at": "2026-01-02T00:00:00Z",
            "scopes": { "boards": "all" }
        }"#,
    );
    let err = grant::load(fixture.data_dir()).unwrap_err();
    assert!(matches!(err, grant::GrantError::Expired { .. }));
}

#[test]
fn grant_malformed_fails_closed() {
    let fixture = common::seeded_fixture("grant_malformed");
    fixture.write_grant("{ not json");
    let err = grant::load(fixture.data_dir()).unwrap_err();
    assert!(matches!(err, grant::GrantError::Invalid(_)));
}

#[test]
fn grant_unknown_board_scope_string_fails_closed() {
    let fixture = common::seeded_fixture("grant_bad_scope");
    fixture.write_grant(
        r#"{
            "grant_id": "bad",
            "created_at": "2026-01-01T00:00:00Z",
            "expires_at": "2999-01-01T00:00:00Z",
            "scopes": { "boards": "everything" }
        }"#,
    );
    assert!(matches!(
        grant::load(fixture.data_dir()).unwrap_err(),
        grant::GrantError::Invalid(_)
    ));
}

#[test]
fn grant_valid_parses_and_deletion_revokes() {
    let fixture = common::seeded_fixture("grant_revoke");
    fixture.write_default_grant();
    let grant = grant::load(fixture.data_dir()).unwrap();
    assert_eq!(grant.grant_id, "test-grant");
    assert!(grant.scopes.boards.allows("anything"));
    assert!(grant.scopes.include_murmurs);

    // Revocation = the app deletes the file; must take effect on next load.
    std::fs::remove_file(fixture.grant_path()).unwrap();
    assert!(matches!(
        grant::load(fixture.data_dir()).unwrap_err(),
        grant::GrantError::Missing(_)
    ));
}

#[test]
fn grant_tolerates_unknown_fields() {
    let fixture = common::seeded_fixture("grant_forward_compat");
    fixture.write_grant(
        r#"{
            "grant_id": "fwd",
            "created_at": "2026-01-01T00:00:00Z",
            "expires_at": "2999-01-01T00:00:00Z",
            "future_field": {"x": 1},
            "scopes": { "boards": ["b-dev"], "future_scope": true }
        }"#,
    );
    let grant = grant::load(fixture.data_dir()).unwrap();
    assert!(grant.scopes.boards.allows("b-dev"));
    assert!(!grant.scopes.boards.allows("b-priv"));
}

#[test]
fn db_missing_fails_closed() {
    let fixture = common::empty_fixture("db_missing");
    assert!(matches!(
        db::open(fixture.data_dir()).unwrap_err(),
        db::DbError::NotFound(_)
    ));
}

#[test]
fn db_newer_schema_fails_closed() {
    let fixture = common::empty_fixture("db_newer");
    let conn = Connection::open(fixture.db_path()).unwrap();
    common::create_schema(&conn, 99);
    drop(conn);
    match db::open(fixture.data_dir()).unwrap_err() {
        db::DbError::SchemaTooNew { found, max } => {
            assert_eq!(found, 99);
            assert_eq!(max, db::MAX_SUPPORTED_SCHEMA);
        }
        other => panic!("expected SchemaTooNew, got {other:?}"),
    }
}

#[test]
fn db_missing_table_fails_closed() {
    let fixture = common::empty_fixture("db_missing_table");
    let conn = Connection::open(fixture.db_path()).unwrap();
    conn.execute_batch("PRAGMA user_version = 26; CREATE TABLE boards (board_id TEXT);")
        .unwrap();
    drop(conn);
    assert!(matches!(
        db::open(fixture.data_dir()).unwrap_err(),
        db::DbError::MissingTable(_)
    ));
}

#[test]
fn db_opens_read_only() {
    let fixture = common::seeded_fixture("db_read_only");
    let conn = db::open(fixture.data_dir()).unwrap();
    let err = conn
        .execute(
            "INSERT INTO boards (board_id, slug, title) VALUES ('x', 'x', 'x')",
            [],
        )
        .unwrap_err();
    assert!(err.to_string().contains("readonly"), "got: {err}");
}
