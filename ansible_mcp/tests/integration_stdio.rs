//! T-210: end-to-end MCP session over stdio against the real binary.
//!
//! The three compliance assertions from the plan:
//! 1. No grant ⇒ every tool call returns a structured denial (AC-1).
//! 2. A board outside the granted scope is invisible through every tool,
//!    including search (AC-2 / Base Rule 2).
//! 3. Another author's private / local-only content is never returned.

mod common;

use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use serde_json::{Value, json};

struct McpSession {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    next_id: i64,
}

impl McpSession {
    fn start(data_dir: &std::path::Path) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_ansible_mcp"))
            .arg("serve")
            .arg("--data-dir")
            .arg(data_dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn ansible-mcp");
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());
        let mut session = McpSession {
            child,
            stdin,
            stdout,
            next_id: 1,
        };
        session.initialize();
        session
    }

    fn send(&mut self, message: Value) {
        let line = serde_json::to_string(&message).unwrap();
        writeln!(self.stdin, "{line}").unwrap();
        self.stdin.flush().unwrap();
    }

    fn recv(&mut self) -> Value {
        let mut line = String::new();
        loop {
            line.clear();
            let n = self.stdout.read_line(&mut line).unwrap();
            assert!(n > 0, "server closed stdout unexpectedly");
            let value: Value = serde_json::from_str(line.trim()).unwrap();
            // Skip server-initiated notifications; return only responses.
            if value.get("id").is_some() {
                return value;
            }
        }
    }

    fn request(&mut self, method: &str, params: Value) -> Value {
        let id = self.next_id;
        self.next_id += 1;
        self.send(json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params }));
        let response = self.recv();
        assert_eq!(response["id"], id, "response id mismatch: {response}");
        response
    }

    fn initialize(&mut self) {
        let response = self.request(
            "initialize",
            json!({
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": { "name": "ansible-mcp-test", "version": "0.0.0" }
            }),
        );
        assert_eq!(
            response["result"]["serverInfo"]["name"], "ansible-mcp",
            "unexpected initialize response: {response}"
        );
        self.send(json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }));
    }

    fn call_tool(&mut self, name: &str, arguments: Value) -> Value {
        let response = self.request(
            "tools/call",
            json!({ "name": name, "arguments": arguments }),
        );
        response["result"].clone()
    }
}

impl Drop for McpSession {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn result_text(result: &Value) -> String {
    result["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

#[test]
fn lists_tools_and_denies_all_calls_without_grant() {
    let fixture = common::seeded_fixture("stdio_no_grant");
    let mut session = McpSession::start(fixture.data_dir());

    // Tools are listed so clients render something useful...
    let tools = session.request("tools/list", json!({}));
    let names: Vec<&str> = tools["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].as_str().unwrap())
        .collect();
    assert_eq!(names.len(), 14);
    assert!(names.contains(&"get_access_scope"));
    assert!(names.contains(&"search_content"));
    assert!(names.contains(&"list_deliberations"));
    assert!(names.contains(&"list_deliberation_responses"));
    // ...and every tool annotation is read-only.
    for tool in tools["result"]["tools"].as_array().unwrap() {
        assert_eq!(
            tool["annotations"]["readOnlyHint"], true,
            "tool {} must be readOnly",
            tool["name"]
        );
    }

    // Compliance assertion 1: every call is denied, as a tool-level error.
    for name in names {
        let result = session.call_tool(
            name,
            json!({ "board_id": "b-dev", "thread_id": "t-1", "did": "x", "query": "x" }),
        );
        assert_eq!(result["isError"], true, "{name} must be denied");
        assert!(
            result_text(&result).contains("Access not granted"),
            "{name} denial must be structured"
        );
    }
}

#[test]
fn narrow_grant_scope_holds_through_every_tool() {
    let fixture = common::seeded_fixture("stdio_narrow");
    fixture.write_narrow_grant();
    let mut session = McpSession::start(fixture.data_dir());

    let boards = session.call_tool("list_boards", json!({}));
    let text = result_text(&boards);
    assert!(text.contains("b-dev"));
    assert!(!text.contains("b-priv"));

    // Compliance assertion 2: the out-of-scope board is invisible everywhere.
    let threads = session.call_tool("list_threads", json!({ "board_id": "b-priv" }));
    assert_eq!(threads["isError"], true);

    let thread = session.call_tool("get_thread", json!({ "thread_id": "t-secret" }));
    assert_eq!(thread["isError"], true);
    assert!(!result_text(&thread).contains("Secret"));

    let search = session.call_tool("search_content", json!({ "query": "zebra" }));
    let text = result_text(&search);
    assert!(!text.contains("Secret zebra cabal"));
    assert!(!text.contains("b-priv"));

    let deliberations = session.call_tool("list_deliberations", json!({}));
    let text = result_text(&deliberations);
    assert!(text.contains("d-dev"));
    assert!(!text.contains("d-private"));

    let private_deliberation = session.call_tool(
        "get_deliberation_report",
        json!({ "deliberation_id": "d-private" }),
    );
    assert_eq!(private_deliberation["isError"], true);
}

#[test]
fn other_authors_private_content_never_returned() {
    let fixture = common::seeded_fixture("stdio_private");
    fixture.write_default_grant();
    let mut session = McpSession::start(fixture.data_dir());

    // Compliance assertion 3, across the two tools that touch content_items.
    for (tool, args) in [
        ("get_murmurs", json!({})),
        ("search_content", json!({ "query": "zebra" })),
    ] {
        let result = session.call_tool(tool, args);
        assert_ne!(result["isError"], true, "{tool} should succeed");
        let text = result_text(&result);
        assert!(
            !text.contains("must never leak"),
            "{tool} leaked another author's private/local-only content"
        );
    }
    // The user's own private murmur IS included (their content, their client).
    let murmurs = session.call_tool("get_murmurs", json!({}));
    assert!(result_text(&murmurs).contains("m-own-private"));
}

#[test]
fn revocation_mid_session_denies_next_call() {
    let fixture = common::seeded_fixture("stdio_revoke");
    fixture.write_default_grant();
    let mut session = McpSession::start(fixture.data_dir());

    let ok = session.call_tool("list_boards", json!({}));
    assert_ne!(ok["isError"], true);

    std::fs::remove_file(fixture.grant_path()).unwrap();

    let denied = session.call_tool("list_boards", json!({}));
    assert_eq!(denied["isError"], true);
    assert!(result_text(&denied).contains("Access not granted"));
}

#[test]
fn audit_log_records_calls_without_content() {
    let fixture = common::seeded_fixture("stdio_audit");
    fixture.write_default_grant();
    let mut session = McpSession::start(fixture.data_dir());

    session.call_tool("get_thread", json!({ "thread_id": "t-1" }));
    session.call_tool("search_content", json!({ "query": "zebras" }));

    let log = std::fs::read_to_string(fixture.data_dir().join("mcp_access_audit.log")).unwrap();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(lines.len(), 2);
    let first: Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(first["tool"], "get_thread");
    assert_eq!(first["grant_id"], "test-grant");
    assert_eq!(first["args"]["thread_id"], "t-1");
    // Never content: post bodies and search terms must not be logged.
    assert!(!log.contains("zebras"));
    assert!(!log.contains("First post"));
}
