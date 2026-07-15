# ansible-mcp

Local, **read-only** MCP server over the Ansible node's synced SQLite
database. Lets MCP-capable AI clients (Claude Desktop, Claude Code, Codex,
…) read the forum/SNS content the user has explicitly granted — and nothing
else.

- Spec: `docs/superpowers/specs/2026-07-14-local-mcp-agent-access-design.md`
- Plan: `docs/superpowers/plans/2026-07-14-local-mcp-agent-access.md`

## Security model (one paragraph)

The binary opens `ansible.db` strictly read-only and only serves after
finding a valid, unexpired `mcp_access_grant.json` next to it — that file is
written by the node app's **Settings → Local AI Access** screen and deleted
on revoke, which takes effect on the next tool call. Queries run through a
fixed table/column allowlist: messenger, wallet, identity, key-backup, and
provider-secret tables are unreachable; `contact_records.local_alias` and
`remote_nodes.access_token` are never selected; other authors' `private` or
`local_only` content is filtered out. Every response carries provenance
(`signature_verified`, `origin_host`, `host_compliance`), every tool call is
audit-logged (metadata only, never content), and the binary holds no keys and
cannot sign or publish anything.

## Setup

The easiest path: enable **Settings → Local AI Access** in the desktop app
and copy the generated snippet — it has the right `--data-dir` baked in.

Desktop builds bundle this binary at `Elix.app/Contents/Helpers/ansible-mcp`
(the "Bundle ansible-mcp" Xcode build phase compiles it from this crate), and
the generated snippets point there automatically, so no separate install is
needed. There is nothing to start manually either way: stdio MCP servers are
spawned by the AI client per session. A separately installed `ansible-mcp` on
PATH is only the fallback for builds without the bundled helper.

Manual (Claude Code):

```bash
claude mcp add ansible -- ansible-mcp serve --data-dir "<data dir>"
```

Manual (Claude Desktop / generic MCP client JSON):

```json
{
  "mcpServers": {
    "ansible": {
      "command": "ansible-mcp",
      "args": ["serve", "--data-dir", "<data dir>"]
    }
  }
}
```

`<data dir>` is the directory containing `ansible.db` — shown on the
settings screen (macOS default:
`~/Library/Application Support/<app bundle>/`).

## Diagnostics

```bash
ansible-mcp doctor --data-dir "<data dir>"
```

Prints database/schema/grant/audit status and exits non-zero when serving
would fail. Common failures:

| Symptom | Cause | Fix |
|---|---|---|
| `Access not granted. No local AI access grant…` | Feature not enabled (or revoked) | Enable in Settings → Local AI Access |
| `…grant expired…` | 90-day grant lapsed | Renew in the same settings screen |
| `…schema (version N) is newer than this binary supports…` | App updated, old binary | Update ansible-mcp to the bundled version |
| `Database not found…` | Wrong `--data-dir`, or app never ran | Copy the exact path from the settings screen |

## Tools

`get_access_scope` · `list_boards` · `list_threads` · `get_thread` ·
`search_content` · `get_author` · `get_follow_feed` · `get_murmurs` — all
read-only, all scope-gated by the grant. Responses are JSON with a
provenance envelope per content item.

## Development

```bash
cargo test            # unit + stdio integration tests (26)
cargo clippy --all-targets
make build-mcp        # from the repo root: release binary
```

`MAX_SUPPORTED_SCHEMA` in `src/db.rs` pins the drift schema version the
queries were reviewed against; bump it only after checking each statement in
`src/queries.rs` against the new migration. The grant JSON schema is shared
with `lib/services/local_ai_access_service.dart` in the app — a golden test
on the Dart side (`test/local_ai_access_service_test.dart`) guards it.
