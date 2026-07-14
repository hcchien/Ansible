//! ansible-mcp entry point (plan T-101, T-104): `serve` (default, MCP over
//! stdio) and `doctor` (setup diagnostics).

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use rmcp::service::{QuitReason, serve_server};
use rmcp::transport::io::stdio;

use ansible_mcp::doctor;
use ansible_mcp::server::AnsibleMcpServer;

#[derive(Parser)]
#[command(
    name = "ansible-mcp",
    version,
    about = "Local, read-only MCP server over the Ansible node's synced data"
)]
struct Cli {
    /// Directory containing ansible.db and mcp_access_grant.json. The Ansible
    /// node app's Settings → Local AI Access page shows the exact value.
    #[arg(long, global = true, env = "ANSIBLE_MCP_DATA_DIR")]
    data_dir: Option<PathBuf>,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Serve MCP over stdio (default).
    Serve,
    /// Diagnose the local setup (database, schema, grant, audit log).
    Doctor,
}

/// Explicit-first resolution (plan D-4): flag/env, else the platform
/// app-support locations the Flutter node uses, else an actionable error.
fn resolve_data_dir(cli_value: Option<PathBuf>) -> Result<PathBuf, String> {
    if let Some(dir) = cli_value {
        return Ok(dir);
    }
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        // macOS: path_provider's getApplicationSupportDirectory.
        candidates.push(home.join("Library/Application Support/Elix"));
        candidates.push(home.join("Library/Application Support/com.example.ansibleNode"));
        // Linux XDG default.
        candidates.push(home.join(".local/share/elix"));
    }
    for dir in candidates {
        if dir.join(ansible_mcp::db::DB_FILE).is_file() {
            return Ok(dir);
        }
    }
    Err(
        "Could not locate the Ansible data directory. Pass --data-dir <path> \
         (the Ansible node app shows the exact path under Settings → Local AI \
         Access) or set ANSIBLE_MCP_DATA_DIR."
            .to_string(),
    )
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let data_dir = match resolve_data_dir(cli.data_dir) {
        Ok(dir) => dir,
        Err(message) => {
            eprintln!("{message}");
            return ExitCode::FAILURE;
        }
    };

    match cli.command.unwrap_or(Command::Serve) {
        Command::Doctor => ExitCode::from(doctor::run(&data_dir) as u8),
        Command::Serve => {
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(err) => {
                    eprintln!("failed to start runtime: {err}");
                    return ExitCode::FAILURE;
                }
            };
            let result = runtime.block_on(async {
                let service = serve_server(AnsibleMcpServer { data_dir }, stdio()).await?;
                service.waiting().await.map_err(anyhow::Error::from)
            });
            match result {
                Ok(QuitReason::JoinError(err)) => {
                    eprintln!("server task failed: {err}");
                    ExitCode::FAILURE
                }
                Ok(_) => ExitCode::SUCCESS,
                Err(err) => {
                    eprintln!("server error: {err}");
                    ExitCode::FAILURE
                }
            }
        }
    }
}
