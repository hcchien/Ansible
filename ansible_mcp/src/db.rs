//! Read-only database access with fail-closed guards (plan T-103).
//!
//! Mirrors the node app's downgrade-guard posture
//! (`ansible_core/store/lib/src/db/app_database.dart`): a schema newer than
//! this binary understands is refused up front with an actionable message
//! instead of failing later with an opaque "no such column".

use std::path::{Path, PathBuf};

use rusqlite::{Connection, OpenFlags};

pub const DB_FILE: &str = "ansible.db";

/// Highest drift `schemaVersion` (stored in `PRAGMA user_version`) this
/// binary's queries were reviewed against. Bumping it requires re-checking
/// every statement in `queries.rs` against the corresponding migration.
pub const MAX_SUPPORTED_SCHEMA: i64 = 35;

/// Tables this binary is allowed to touch, ever (AC-2). `queries.rs` holds the
/// statements; this list is what the open-time guard verifies and what the
/// compliance tests assert against. `remote_nodes` carries an `access_token`
/// column — the allowlist is column-level in each query; that column is never
/// selected.
pub const ALLOWLISTED_TABLES: &[&str] = &[
    "boards",
    "threads",
    "posts",
    "content_items",
    "follow_edges",
    "follow_targets",
    "contact_records",
    "did_reputations",
    "forum_hosts",
    "remote_nodes",
    "board_subscriptions",
    "board_sync_configs",
    "deliberation_exports",
];

#[derive(Debug)]
pub enum DbError {
    NotFound(PathBuf),
    SchemaTooNew { found: i64, max: i64 },
    MissingTable(String),
    Sqlite(rusqlite::Error),
}

impl From<rusqlite::Error> for DbError {
    fn from(err: rusqlite::Error) -> Self {
        DbError::Sqlite(err)
    }
}

impl DbError {
    pub fn denial_message(&self) -> String {
        match self {
            DbError::NotFound(path) => format!(
                "Database not found at {}. Run the Ansible node app at least once \
                 (and check the --data-dir path) before connecting an AI client.",
                path.display()
            ),
            DbError::SchemaTooNew { found, max } => format!(
                "The Ansible database schema (version {found}) is newer than this \
                 ansible-mcp binary supports (max {max}). Update ansible-mcp to the \
                 version bundled with your Ansible app."
            ),
            DbError::MissingTable(table) => format!(
                "The Ansible database is missing the expected table \"{table}\". \
                 It may predate the Local AI Access feature — update and run the \
                 Ansible node app, then retry."
            ),
            DbError::Sqlite(err) => format!("Could not read the Ansible database: {err}"),
        }
    }
}

/// Open `ansible.db` strictly read-only, verifying the guard chain:
/// file exists → readable → schema version supported → allowlisted tables
/// present. A fresh connection per tool call keeps the binary stateless and
/// picks up app-side restores or migrations immediately.
pub fn open(data_dir: &Path) -> Result<Connection, DbError> {
    let path = data_dir.join(DB_FILE);
    if !path.is_file() {
        return Err(DbError::NotFound(path));
    }
    let conn = Connection::open_with_flags(
        &path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    // The app may hold write locks briefly (drift defaults to a rollback
    // journal, not WAL); wait a little instead of surfacing SQLITE_BUSY.
    conn.busy_timeout(std::time::Duration::from_millis(3000))?;

    let found: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if found > MAX_SUPPORTED_SCHEMA {
        return Err(DbError::SchemaTooNew {
            found,
            max: MAX_SUPPORTED_SCHEMA,
        });
    }
    for table in ALLOWLISTED_TABLES {
        let present: bool = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
            [table],
            |row| row.get(0),
        )?;
        if !present {
            return Err(DbError::MissingTable((*table).to_string()));
        }
    }
    Ok(conn)
}

/// `PRAGMA journal_mode` for diagnostics (doctor).
pub fn journal_mode(conn: &Connection) -> Result<String, rusqlite::Error> {
    conn.query_row("PRAGMA journal_mode", [], |row| row.get(0))
}
