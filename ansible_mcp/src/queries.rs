//! The single allowlisted query path (plan T-201, AC-2).
//!
//! Every SQL statement in the binary lives in this module as a prepared
//! statement over the tables in `db::ALLOWLISTED_TABLES`, with column-level
//! selection (e.g. `contact_records.local_alias` and
//! `remote_nodes.access_token` are never selected). Grant scope filtering is
//! applied inside each query, never post-hoc.
//!
//! Every content row is wrapped in the provenance envelope (AC-4):
//! `{ author_did, author_display, created_at, signature_verified,
//!    origin_host, host_compliance, content }`.

use std::collections::HashMap;

use rusqlite::{Connection, params_from_iter};
use serde_json::{Map, Value, json};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::grant::{BoardScope, Grant};

pub const DEFAULT_PAGE: usize = 50;
pub const MAX_PAGE: usize = 200;
pub const SEARCH_LIMIT: usize = 25;
pub const SNIPPET_RADIUS: usize = 160;

#[derive(Debug)]
pub enum QueryError {
    /// The argument is invalid or references something outside the grant.
    /// Deliberately indistinguishable from "does not exist" for out-of-scope
    /// ids so the tool surface does not leak what exists beyond the scope.
    NotFound(String),
    BadArgument(String),
    ScopeDisabled(&'static str),
    Sqlite(rusqlite::Error),
}

impl From<rusqlite::Error> for QueryError {
    fn from(err: rusqlite::Error) -> Self {
        QueryError::Sqlite(err)
    }
}

impl QueryError {
    pub fn message(&self) -> String {
        match self {
            QueryError::NotFound(what) => format!("{what} was not found in the granted scope."),
            QueryError::BadArgument(msg) => format!("Invalid argument: {msg}"),
            QueryError::ScopeDisabled(scope) => format!(
                "The \"{scope}\" scope is not enabled in the local AI access grant. \
                 It can be enabled in the Ansible node app (Settings → Local AI Access)."
            ),
            QueryError::Sqlite(err) => format!("Database query failed: {err}"),
        }
    }
}

fn epoch_to_rfc3339(epoch: i64) -> String {
    OffsetDateTime::from_unix_timestamp(epoch)
        .ok()
        .and_then(|ts| ts.format(&Rfc3339).ok())
        .unwrap_or_else(|| epoch.to_string())
}

/// Provenance envelope (AC-4). `host_compliance` is `"unknown"` whenever the
/// origin host has not declared (or the store has not persisted) a level.
fn envelope(
    author_did: &str,
    author_display: Option<String>,
    created_epoch: i64,
    signature_verified: bool,
    origin: Option<&HostProvenance>,
    content: Value,
) -> Value {
    json!({
        "author_did": author_did,
        "author_display": author_display,
        "created_at": epoch_to_rfc3339(created_epoch),
        "signature_verified": signature_verified,
        "origin_host": origin.map(|h| h.name.clone()),
        "host_compliance": origin
            .and_then(|h| h.compliance.clone())
            .unwrap_or_else(|| "unknown".to_string()),
        "content": content,
    })
}

#[derive(Debug, Clone)]
pub struct HostProvenance {
    pub name: String,
    pub compliance: Option<String>,
}

/// board_id → origin host, for boards that were synced from elsewhere.
/// Local-only boards are absent (origin_host = null in the envelope).
/// Column allowlist: `remote_nodes.access_token` is never selected.
pub fn board_host_map(conn: &Connection) -> Result<HashMap<String, HostProvenance>, QueryError> {
    let mut map = HashMap::new();
    let mut stmt = conn.prepare(
        "SELECT bs.local_board_id, fh.display_name
           FROM board_subscriptions bs
           JOIN forum_hosts fh ON fh.forum_host_id = bs.forum_host_id",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    for row in rows {
        let (board_id, name) = row?;
        map.insert(
            board_id,
            HostProvenance {
                name,
                // forum_hosts has no compliance column yet (compliance-review
                // gap #2); served as "unknown" per AC-4.
                compliance: None,
            },
        );
    }
    let mut stmt = conn.prepare(
        "SELECT bsc.board_id, rn.name, rn.constitution_compliance
           FROM board_sync_configs bsc
           JOIN remote_nodes rn ON rn.node_id = bsc.remote_node_id",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<String>>(2)?,
        ))
    })?;
    for row in rows {
        let (board_id, name, compliance) = row?;
        map.entry(board_id)
            .or_insert(HostProvenance { name, compliance });
    }
    Ok(map)
}

/// Builds `(sql_fragment, params)` for the board-scope filter on a given
/// column. The column name is a compile-time constant at every call site;
/// only values are bound.
fn board_scope_filter(column: &'static str, scope: &BoardScope) -> (String, Vec<String>) {
    match scope {
        BoardScope::All => (String::new(), Vec::new()),
        BoardScope::Ids(ids) => {
            if ids.is_empty() {
                // Empty grant scope matches nothing; fail closed.
                (format!(" AND {column} IN (NULL)"), Vec::new())
            } else {
                let placeholders = vec!["?"; ids.len()].join(", ");
                (format!(" AND {column} IN ({placeholders})"), ids.clone())
            }
        }
    }
}

fn escape_like(term: &str) -> String {
    term.replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn snippet(body: &str, term: &str) -> String {
    let lower_body = body.to_lowercase();
    let lower_term = term.to_lowercase();
    let hit = lower_body.find(&lower_term).unwrap_or(0);
    // Clamp to char boundaries so multi-byte content never panics.
    let mut start = hit.saturating_sub(SNIPPET_RADIUS);
    while start > 0 && !body.is_char_boundary(start) {
        start -= 1;
    }
    let mut end = (hit + term.len() + SNIPPET_RADIUS).min(body.len());
    while end < body.len() && !body.is_char_boundary(end) {
        end += 1;
    }
    let mut out = String::new();
    if start > 0 {
        out.push('…');
    }
    out.push_str(&body[start..end]);
    if end < body.len() {
        out.push('…');
    }
    out
}

fn clamp_limit(limit: Option<u64>) -> usize {
    limit
        .map(|l| (l as usize).clamp(1, MAX_PAGE))
        .unwrap_or(DEFAULT_PAGE)
}

/// Opaque keyset cursor `"<epoch>:<id>"`.
fn parse_cursor(cursor: Option<&str>) -> Result<Option<(i64, String)>, QueryError> {
    match cursor {
        None => Ok(None),
        Some(raw) => {
            let (epoch, id) = raw
                .split_once(':')
                .ok_or_else(|| QueryError::BadArgument("malformed cursor".into()))?;
            let epoch: i64 = epoch
                .parse()
                .map_err(|_| QueryError::BadArgument("malformed cursor".into()))?;
            Ok(Some((epoch, id.to_string())))
        }
    }
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

pub fn get_access_scope(
    conn: &Connection,
    grant: &Grant,
    data_dir: &std::path::Path,
) -> Result<Value, QueryError> {
    let schema_version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    let last_sync = std::fs::metadata(data_dir.join(crate::db::DB_FILE))
        .and_then(|meta| meta.modified())
        .ok()
        .map(|mtime| {
            OffsetDateTime::from(mtime)
                .format(&Rfc3339)
                .unwrap_or_default()
        });
    let boards = match &grant.scopes.boards {
        BoardScope::All => json!("all"),
        BoardScope::Ids(ids) => json!(ids),
    };
    Ok(json!({
        "grant_id": grant.grant_id,
        "expires_at": grant.expires_at.format(&Rfc3339).unwrap_or_default(),
        "scopes": {
            "boards": boards,
            "include_murmurs": grant.scopes.include_murmurs,
            "include_follow_feed": grant.scopes.include_follow_feed,
        },
        "schema_version": schema_version,
        "last_sync_at": last_sync,
        "notes": "Read-only access to locally synced content within the scopes above. \
                  Content freshness equals the node app's last sync.",
    }))
}

pub fn list_boards(conn: &Connection, grant: &Grant) -> Result<Value, QueryError> {
    let hosts = board_host_map(conn)?;
    let (filter, params) = board_scope_filter("board_id", &grant.scopes.boards);
    let sql = format!(
        "SELECT board_id, slug, title, description
           FROM boards
          WHERE is_deleted = 0{filter}
          ORDER BY title"
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok(json!({
            "board_id": row.get::<_, String>(0)?,
            "slug": row.get::<_, String>(1)?,
            "title": row.get::<_, String>(2)?,
            "description": row.get::<_, Option<String>>(3)?,
        }))
    })?;
    let mut boards = Vec::new();
    for row in rows {
        let mut board = row?;
        let board_id = board["board_id"].as_str().unwrap_or_default().to_string();
        let origin = hosts.get(&board_id);
        board["origin_host"] = json!(origin.map(|h| h.name.clone()));
        board["host_compliance"] = json!(
            origin
                .and_then(|h| h.compliance.clone())
                .unwrap_or_else(|| "unknown".to_string())
        );
        boards.push(board);
    }
    Ok(json!({ "boards": boards }))
}

fn require_board_in_scope(
    conn: &Connection,
    grant: &Grant,
    board_id: &str,
) -> Result<(), QueryError> {
    if !grant.scopes.boards.allows(board_id) {
        return Err(QueryError::NotFound(format!("Board \"{board_id}\"")));
    }
    let exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM boards WHERE board_id = ?1 AND is_deleted = 0)",
        [board_id],
        |row| row.get(0),
    )?;
    if !exists {
        return Err(QueryError::NotFound(format!("Board \"{board_id}\"")));
    }
    Ok(())
}

pub fn list_threads(
    conn: &Connection,
    grant: &Grant,
    board_id: &str,
    cursor: Option<&str>,
    limit: Option<u64>,
) -> Result<Value, QueryError> {
    require_board_in_scope(conn, grant, board_id)?;
    let limit = clamp_limit(limit);
    let cursor = parse_cursor(cursor)?;
    let mut sql = String::from(
        "SELECT thread_id, title, author_id, created_at, updated_at
           FROM threads
          WHERE board_id = ?1 AND is_deleted = 0",
    );
    let mut params: Vec<String> = vec![board_id.to_string()];
    if let Some((epoch, id)) = &cursor {
        sql.push_str(" AND (updated_at < ?2 OR (updated_at = ?2 AND thread_id > ?3))");
        params.push(epoch.to_string());
        params.push(id.clone());
    }
    sql.push_str(" ORDER BY updated_at DESC, thread_id ASC LIMIT ?");
    params.push((limit + 1).to_string());

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, i64>(3)?,
            row.get::<_, i64>(4)?,
        ))
    })?;
    let mut threads = Vec::new();
    let mut next_cursor: Option<String> = None;
    let mut last_key: Option<(i64, String)> = None;
    for row in rows {
        let (thread_id, title, author_id, created_at, updated_at) = row?;
        if threads.len() == limit {
            if let Some((epoch, id)) = last_key {
                next_cursor = Some(format!("{epoch}:{id}"));
            }
            break;
        }
        last_key = Some((updated_at, thread_id.clone()));
        threads.push(json!({
            "thread_id": thread_id,
            "title": title,
            "author_did": author_id,
            "created_at": epoch_to_rfc3339(created_at),
            "updated_at": epoch_to_rfc3339(updated_at),
        }));
    }
    Ok(json!({ "board_id": board_id, "threads": threads, "next_cursor": next_cursor }))
}

/// Thread with a flat post list; `parent_post_id` lets the client model
/// reconstruct the tree (plan T-204).
pub fn get_thread(
    conn: &Connection,
    grant: &Grant,
    thread_id: &str,
    cursor: Option<&str>,
    limit: Option<u64>,
) -> Result<Value, QueryError> {
    let hosts = board_host_map(conn)?;
    let thread = conn
        .query_row(
            "SELECT thread_id, board_id, title, author_id, created_at
               FROM threads
              WHERE thread_id = ?1 AND is_deleted = 0",
            [thread_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            },
        )
        .map(Some)
        .or_else(|err| match err {
            rusqlite::Error::QueryReturnedNoRows => Ok(None),
            other => Err(other),
        })?;
    let Some((thread_id, board_id, title, author_id, created_at)) = thread else {
        return Err(QueryError::NotFound(format!("Thread \"{thread_id}\"")));
    };
    if !grant.scopes.boards.allows(&board_id) {
        // Same shape as "does not exist" — out-of-scope ids must not confirm
        // existence (compliance test in tests/integration_stdio.rs).
        return Err(QueryError::NotFound(format!("Thread \"{thread_id}\"")));
    }

    let limit = clamp_limit(limit);
    let cursor = parse_cursor(cursor)?;
    let mut sql = String::from(
        "SELECT p.post_id, p.parent_post_id, p.author_id, p.content,
                p.created_at, p.signature_verified, c.display_name
           FROM posts p
           LEFT JOIN contact_records c ON c.subject_did = p.author_id
          WHERE p.thread_id = ?1 AND p.is_deleted = 0",
    );
    let mut params: Vec<String> = vec![thread_id.clone()];
    if let Some((epoch, id)) = &cursor {
        sql.push_str(" AND (p.created_at > ?2 OR (p.created_at = ?2 AND p.post_id > ?3))");
        params.push(epoch.to_string());
        params.push(id.clone());
    }
    sql.push_str(" ORDER BY p.created_at ASC, p.post_id ASC LIMIT ?");
    params.push((limit + 1).to_string());

    let origin = hosts.get(&board_id);
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, Option<String>>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, i64>(4)?,
            row.get::<_, bool>(5)?,
            row.get::<_, Option<String>>(6)?,
        ))
    })?;
    let mut posts = Vec::new();
    let mut next_cursor: Option<String> = None;
    let mut last_key: Option<(i64, String)> = None;
    for row in rows {
        let (post_id, parent_post_id, author_did, content, post_created, sig, display) = row?;
        if posts.len() == limit {
            if let Some((epoch, id)) = last_key {
                next_cursor = Some(format!("{epoch}:{id}"));
            }
            break;
        }
        last_key = Some((post_created, post_id.clone()));
        posts.push(envelope(
            &author_did,
            display,
            post_created,
            sig,
            origin,
            json!({ "post_id": post_id, "parent_post_id": parent_post_id, "body": content }),
        ));
    }
    Ok(json!({
        "thread_id": thread_id,
        "board_id": board_id,
        "title": title,
        "author_did": author_id,
        "created_at": epoch_to_rfc3339(created_at),
        "origin_host": origin.map(|h| h.name.clone()),
        "host_compliance": origin
            .and_then(|h| h.compliance.clone())
            .unwrap_or_else(|| "unknown".to_string()),
        "posts": posts,
        "next_cursor": next_cursor,
    }))
}

pub fn search_content(conn: &Connection, grant: &Grant, query: &str) -> Result<Value, QueryError> {
    let term = query.trim();
    if term.is_empty() {
        return Err(QueryError::BadArgument("query must not be empty".into()));
    }
    let hosts = board_host_map(conn)?;
    let pattern = format!("%{}%", escape_like(term));
    let mut results = Vec::new();

    // Posts within granted boards.
    let (filter, scope_params) = board_scope_filter("p.board_id", &grant.scopes.boards);
    let sql = format!(
        "SELECT p.post_id, p.thread_id, p.board_id, p.author_id, p.content,
                p.created_at, p.signature_verified, c.display_name
           FROM posts p
           LEFT JOIN contact_records c ON c.subject_did = p.author_id
          WHERE p.is_deleted = 0 AND p.content LIKE ?1 ESCAPE '\\'{filter}
          ORDER BY p.created_at DESC LIMIT {SEARCH_LIMIT}"
    );
    let mut params: Vec<String> = vec![pattern.clone()];
    params.extend(scope_params);
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, i64>(5)?,
            row.get::<_, bool>(6)?,
            row.get::<_, Option<String>>(7)?,
        ))
    })?;
    for row in rows {
        let (post_id, thread_id, board_id, author_did, content, created, sig, display) = row?;
        results.push(envelope(
            &author_did,
            display,
            created,
            sig,
            hosts.get(&board_id),
            json!({
                "kind": "post",
                "post_id": post_id,
                "thread_id": thread_id,
                "board_id": board_id,
                "snippet": snippet(&content, term),
            }),
        ));
    }

    // Thread titles within granted boards.
    let (filter, scope_params) = board_scope_filter("t.board_id", &grant.scopes.boards);
    let sql = format!(
        "SELECT t.thread_id, t.board_id, t.title, t.author_id, t.created_at
           FROM threads t
          WHERE t.is_deleted = 0 AND t.title LIKE ?1 ESCAPE '\\'{filter}
          ORDER BY t.created_at DESC LIMIT {SEARCH_LIMIT}"
    );
    let mut params: Vec<String> = vec![pattern.clone()];
    params.extend(scope_params);
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, i64>(4)?,
        ))
    })?;
    for row in rows {
        let (thread_id, board_id, thread_title, author_did, created) = row?;
        results.push(envelope(
            &author_did,
            None,
            created,
            false,
            hosts.get(&board_id),
            json!({
                "kind": "thread",
                "thread_id": thread_id,
                "board_id": board_id,
                "snippet": snippet(&thread_title, term),
            }),
        ));
    }

    // Murmurs/notes, only when in scope.
    if grant.scopes.include_murmurs {
        let sql = format!(
            "SELECT ci.content_item_id, ci.author_did, ci.title, ci.body, ci.created_at,
                    c.display_name, ci.visibility, ci.local_only
               FROM content_items ci
               LEFT JOIN contact_records c ON c.subject_did = ci.author_did
              WHERE ci.is_deleted = 0
                AND ci.mode IN ('murmur', 'note')
                AND (ci.title LIKE ?1 ESCAPE '\\' OR ci.body LIKE ?1 ESCAPE '\\')
              ORDER BY ci.created_at DESC LIMIT {SEARCH_LIMIT}"
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map([&pattern], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, Option<String>>(5)?,
                row.get::<_, String>(6)?,
                row.get::<_, bool>(7)?,
            ))
        })?;
        for row in rows {
            let (item_id, author_did, item_title, body, created, display, visibility, local_only) =
                row?;
            if !murmur_visible(grant, &author_did, &visibility, local_only) {
                continue;
            }
            let haystack = format!("{} {}", item_title.clone().unwrap_or_default(), body);
            results.push(envelope(
                &author_did,
                display,
                created,
                false,
                None,
                json!({
                    "kind": "murmur",
                    "content_item_id": item_id,
                    "title": item_title,
                    "snippet": snippet(&haystack, term),
                }),
            ));
        }
    }

    results.truncate(SEARCH_LIMIT);
    Ok(json!({ "query": term, "results": results }))
}

pub fn get_author(conn: &Connection, did: &str) -> Result<Value, QueryError> {
    // Column allowlist: local_alias (the user's private nickname for the
    // contact) is deliberately not selected.
    let profile = conn
        .query_row(
            "SELECT subject_did, handle, display_name, avatar_url
               FROM contact_records
              WHERE subject_did = ?1",
            [did],
            |row| {
                Ok(json!({
                    "did": row.get::<_, String>(0)?,
                    "handle": row.get::<_, Option<String>>(1)?,
                    "display_name": row.get::<_, Option<String>>(2)?,
                    "avatar_url": row.get::<_, Option<String>>(3)?,
                }))
            },
        )
        .map(Some)
        .or_else(|err| match err {
            rusqlite::Error::QueryReturnedNoRows => Ok(None),
            other => Err(other),
        })?;
    let reputation: Option<String> = conn
        .query_row(
            "SELECT tier FROM did_reputations WHERE did = ?1",
            [did],
            |row| row.get(0),
        )
        .map(Some)
        .or_else(|err| match err {
            rusqlite::Error::QueryReturnedNoRows => Ok(None),
            other => Err(other),
        })?;
    let mut result = profile.unwrap_or_else(|| json!({ "did": did }));
    result["reputation_tier"] = json!(reputation);
    Ok(result)
}

fn murmur_visible(grant: &Grant, author_did: &str, visibility: &str, local_only: bool) -> bool {
    if grant.local_author_dids.iter().any(|d| d == author_did) {
        // The user's own content is theirs to share with their own AI client.
        return true;
    }
    visibility != "private" && !local_only
}

pub fn get_murmurs(
    conn: &Connection,
    grant: &Grant,
    cursor: Option<&str>,
    limit: Option<u64>,
) -> Result<Value, QueryError> {
    if !grant.scopes.include_murmurs {
        return Err(QueryError::ScopeDisabled("include_murmurs"));
    }
    let limit = clamp_limit(limit);
    let cursor = parse_cursor(cursor)?;
    let mut sql = String::from(
        "SELECT ci.content_item_id, ci.author_did, ci.mode, ci.title, ci.body,
                ci.created_at, ci.visibility, ci.local_only, c.display_name
           FROM content_items ci
           LEFT JOIN contact_records c ON c.subject_did = ci.author_did
          WHERE ci.is_deleted = 0 AND ci.mode IN ('murmur', 'note')",
    );
    let mut params: Vec<String> = Vec::new();
    if let Some((epoch, id)) = &cursor {
        sql.push_str(
            " AND (ci.created_at < ?1 OR (ci.created_at = ?1 AND ci.content_item_id > ?2))",
        );
        params.push(epoch.to_string());
        params.push(id.clone());
    }
    sql.push_str(" ORDER BY ci.created_at DESC, ci.content_item_id ASC LIMIT ?");
    // Over-fetch to allow for visibility filtering plus has-more detection.
    params.push((limit * 3 + 1).to_string());

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, Option<String>>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, i64>(5)?,
            row.get::<_, String>(6)?,
            row.get::<_, bool>(7)?,
            row.get::<_, Option<String>>(8)?,
        ))
    })?;
    let mut items = Vec::new();
    let mut next_cursor: Option<String> = None;
    let mut last_key: Option<(i64, String)> = None;
    for row in rows {
        let (item_id, author_did, mode, title, body, created, visibility, local_only, display) =
            row?;
        if !murmur_visible(grant, &author_did, &visibility, local_only) {
            continue;
        }
        if items.len() == limit {
            if let Some((epoch, id)) = last_key {
                next_cursor = Some(format!("{epoch}:{id}"));
            }
            break;
        }
        last_key = Some((created, item_id.clone()));
        items.push(envelope(
            &author_did,
            display,
            created,
            false,
            None,
            json!({
                "content_item_id": item_id,
                "mode": mode,
                "title": title,
                "body": body,
            }),
        ));
    }
    Ok(json!({ "items": items, "next_cursor": next_cursor }))
}

/// Following feed derived from accepted outbound follow edges (plan D-6):
/// posts authored by followed users plus threads in followed boards.
pub fn get_follow_feed(
    conn: &Connection,
    grant: &Grant,
    cursor: Option<&str>,
    limit: Option<u64>,
) -> Result<Value, QueryError> {
    if !grant.scopes.include_follow_feed {
        return Err(QueryError::ScopeDisabled("include_follow_feed"));
    }
    let hosts = board_host_map(conn)?;
    let limit = clamp_limit(limit);
    let cursor = parse_cursor(cursor)?;

    // Followed author DIDs and board ids. Enum strings verified against
    // ansible_core/store entities: direction=outbound, status=accepted,
    // target_type ∈ {user, board}.
    let mut followed_dids: Vec<String> = Vec::new();
    let mut followed_boards: Vec<String> = Vec::new();
    let mut stmt = conn.prepare(
        "SELECT ft.target_type, ft.did, ft.board_id
           FROM follow_edges fe
           JOIN follow_targets ft ON ft.target_id = fe.target_id
          WHERE fe.direction = 'outbound' AND fe.status = 'accepted'
            AND ft.is_deleted = 0",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, Option<String>>(1)?,
            row.get::<_, Option<String>>(2)?,
        ))
    })?;
    for row in rows {
        let (target_type, did, board_id) = row?;
        match target_type.as_str() {
            "user" => {
                if let Some(did) = did {
                    followed_dids.push(did);
                }
            }
            "board" => {
                if let Some(board_id) = board_id {
                    followed_boards.push(board_id);
                }
            }
            _ => {}
        }
    }
    // Followed boards must still fall inside the granted board scope.
    followed_boards.retain(|id| grant.scopes.boards.allows(id));

    if followed_dids.is_empty() && followed_boards.is_empty() {
        return Ok(json!({ "items": [], "next_cursor": null }));
    }

    let mut clauses: Vec<String> = Vec::new();
    let mut params: Vec<String> = Vec::new();
    if !followed_dids.is_empty() {
        let placeholders = vec!["?"; followed_dids.len()].join(", ");
        clauses.push(format!("p.author_id IN ({placeholders})"));
        params.extend(followed_dids.iter().cloned());
    }
    if !followed_boards.is_empty() {
        let placeholders = vec!["?"; followed_boards.len()].join(", ");
        clauses.push(format!("p.board_id IN ({placeholders})"));
        params.extend(followed_boards.iter().cloned());
    }
    // Author-followed posts must still fall inside the granted board scope.
    let (scope_filter, scope_params) = board_scope_filter("p.board_id", &grant.scopes.boards);
    let mut sql = format!(
        "SELECT p.post_id, p.thread_id, p.board_id, p.author_id, p.content,
                p.created_at, p.signature_verified, c.display_name
           FROM posts p
           LEFT JOIN contact_records c ON c.subject_did = p.author_id
          WHERE p.is_deleted = 0 AND ({}){scope_filter}",
        clauses.join(" OR ")
    );
    params.extend(scope_params);
    if let Some((epoch, id)) = &cursor {
        sql.push_str(" AND (p.created_at < ? OR (p.created_at = ? AND p.post_id > ?))");
        params.push(epoch.to_string());
        params.push(epoch.to_string());
        params.push(id.clone());
    }
    sql.push_str(" ORDER BY p.created_at DESC, p.post_id ASC LIMIT ?");
    params.push((limit + 1).to_string());

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params_from_iter(params.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, i64>(5)?,
            row.get::<_, bool>(6)?,
            row.get::<_, Option<String>>(7)?,
        ))
    })?;
    let mut items = Vec::new();
    let mut next_cursor: Option<String> = None;
    let mut last_key: Option<(i64, String)> = None;
    for row in rows {
        let (post_id, thread_id, board_id, author_did, content, created, sig, display) = row?;
        if items.len() == limit {
            if let Some((epoch, id)) = last_key {
                next_cursor = Some(format!("{epoch}:{id}"));
            }
            break;
        }
        last_key = Some((created, post_id.clone()));
        items.push(envelope(
            &author_did,
            display,
            created,
            sig,
            hosts.get(&board_id),
            json!({
                "kind": "post",
                "post_id": post_id,
                "thread_id": thread_id,
                "board_id": board_id,
                "body": content,
            }),
        ));
    }
    Ok(json!({ "items": items, "next_cursor": next_cursor }))
}

/// Row-count estimate for the audit log: number of top-level entries a tool
/// response carries, without inspecting content.
pub fn result_row_count(value: &Value) -> usize {
    for key in ["boards", "threads", "posts", "results", "items"] {
        if let Some(arr) = value.get(key).and_then(Value::as_array) {
            return arr.len();
        }
    }
    1
}

/// Strips any key not relevant to scope from tool arguments before they reach
/// the audit log (defense in depth; args are ids/cursors only today).
pub fn audit_args(args: &Map<String, Value>) -> Value {
    let mut out = Map::new();
    for key in ["board_id", "thread_id", "did", "cursor", "limit"] {
        if let Some(v) = args.get(key) {
            out.insert(key.to_string(), v.clone());
        }
    }
    Value::Object(out)
}
