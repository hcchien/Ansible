//! `ansible-mcp doctor` — setup diagnostics (plan T-105). Prints status only;
//! never content. Exit code 0 when serving would work, 1 otherwise.

use std::path::Path;

use time::format_description::well_known::Rfc3339;

use crate::{audit, db, grant};

pub fn run(data_dir: &Path) -> i32 {
    let mut healthy = true;
    println!("ansible-mcp doctor");
    println!("  data dir:      {}", data_dir.display());

    let db_path = data_dir.join(db::DB_FILE);
    match db::open(data_dir) {
        Ok(conn) => {
            let version: i64 = conn
                .query_row("PRAGMA user_version", [], |row| row.get(0))
                .unwrap_or(-1);
            let journal = db::journal_mode(&conn).unwrap_or_else(|_| "?".into());
            println!("  database:      ok ({})", db_path.display());
            println!(
                "  schema:        {version} (max supported {})",
                db::MAX_SUPPORTED_SCHEMA
            );
            println!("  journal mode:  {journal}");
        }
        Err(err) => {
            healthy = false;
            println!("  database:      FAILED — {}", err.denial_message());
        }
    }

    match grant::load(data_dir) {
        Ok(grant) => {
            println!(
                "  grant:         ok (id {}, expires {})",
                grant.grant_id,
                grant.expires_at.format(&Rfc3339).unwrap_or_default()
            );
        }
        Err(err) => {
            healthy = false;
            println!("  grant:         FAILED — {}", err.denial_message());
        }
    }

    println!(
        "  audit log:     {}",
        data_dir.join(audit::AUDIT_FILE).display()
    );
    println!(
        "  status:        {}",
        if healthy { "ready" } else { "not ready" }
    );
    i32::from(!healthy)
}
