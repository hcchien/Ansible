//! ansible-mcp — local, read-only MCP server over the Ansible node's synced
//! SQLite database.
//!
//! Spec: docs/superpowers/specs/2026-07-14-local-mcp-agent-access-design.md
//! Plan: docs/superpowers/plans/2026-07-14-local-mcp-agent-access.md
//!
//! Constitution acceptance criteria enforced here:
//! - AC-1: grant enforcement is in-binary and fail-closed (grant.rs, server.rs)
//! - AC-2: the table/column allowlist in queries.rs is the only query path
//! - AC-3: SQLITE_OPEN_READ_ONLY, no signing, no network listener
//! - AC-4: every content response carries provenance (queries.rs envelope)

pub mod audit;
pub mod db;
pub mod doctor;
pub mod grant;
pub mod queries;
pub mod server;
