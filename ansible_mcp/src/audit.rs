//! Append-only tool-call audit log (plan T-209).
//!
//! One JSON line per tool call: timestamp, grant id, tool name, scope-relevant
//! arguments (board/thread ids, cursors), row count — never content (Base
//! Rule 2/4). A failed audit write fails the tool call: no unaudited reads.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::Path;

use serde_json::{Value, json};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

pub const AUDIT_FILE: &str = "mcp_access_audit.log";
const ROTATE_BYTES: u64 = 5 * 1024 * 1024;

pub fn record(
    data_dir: &Path,
    grant_id: &str,
    tool: &str,
    scope_args: &Value,
    row_count: usize,
) -> std::io::Result<()> {
    let path = data_dir.join(AUDIT_FILE);
    if let Ok(meta) = std::fs::metadata(&path)
        && meta.len() > ROTATE_BYTES
    {
        let backup = data_dir.join(format!("{AUDIT_FILE}.1"));
        std::fs::rename(&path, backup)?;
    }
    let line = json!({
        "ts": OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default(),
        "grant_id": grant_id,
        "tool": tool,
        "args": scope_args,
        "row_count": row_count,
    });
    let mut file: File = OpenOptions::new().create(true).append(true).open(&path)?;
    writeln!(file, "{line}")?;
    Ok(())
}
