# Local MCP Agent Access — `ansible_mcp` Implementation Plan

> Status: **Implemented 2026-07-14** (Phases 1–4; T-403 real-client manual
> verification pending — see Phase 4 notes)
> Date: 2026-07-14
> Spec: `docs/superpowers/specs/2026-07-14-local-mcp-agent-access-design.md`
> Backlog: `docs/superpowers/todos/2026-05-16-llm-plugin-mcp-access.md` (Phase 3)
>
> Constitution Review: covered by the spec above (verdict: compliant,
> conditional). The four conditions are restated below as hard acceptance
> criteria; this plan adds no new identity/storage/sync behavior beyond the
> spec.

## Constitution Acceptance Criteria (from the spec verdict)

Every phase below must preserve all four; they are release blockers:

- [x] **AC-1** Grant enforcement lives in the binary and fails closed — no
  grant file, expired grant, or unparseable grant ⇒ every tool returns a
  structured "access not granted" error. UI gating alone is not compliance.
- [x] **AC-2** The table allowlist is the only query path. No raw-SQL tool, no
  dynamic table names, all SQL is prepared statements defined in one module.
- [x] **AC-3** V1 is read-only and desktop-only: `SQLITE_OPEN_READ_ONLY`, no
  signing code, no key material, no network listener.
- [x] **AC-4** Every content response carries provenance
  (`signature_verified`, `origin_host`, `host_compliance`); until host
  compliance is persisted locally, the field is `"unknown"`, never omitted.

## Ground Truth (verified against the repo, 2026-07-14)

Facts the implementation relies on — re-verify if the store changes:

- DB file: `ansible.db` in Flutter `getApplicationSupportDirectory()`
  (`ansible_node/app/lib/main.dart:157-164`), written by drift's
  `NativeDatabase` with WAL.
- Drift generates **snake_case** SQL names: table `content_items`, columns
  `content_item_id`, `signature_verified`, `board_id`, etc.
- `DateTimeColumn` is stored as **INTEGER unix epoch seconds** (drift default;
  no `build.yaml` overrides in `ansible_core/store`). `BoolColumn` is INTEGER
  0/1.
- Schema version lives in `PRAGMA user_version`; currently **26**. The app
  already has a downgrade guard (`app_database.dart:118-134`,
  `DatabaseDowngradeError`) — the binary mirrors that pattern.
- `content_items.mode` ∈ `murmur | note | post | discussion`;
  `content_items.visibility` ∈ `private | unlisted | public`; plus
  `local_only` flag (`ansible_core/store/lib/src/entities/content_item.dart`).
- Follow model: `follow_edges` (status/direction/visibility) →
  `follow_targets`; there is no locally materialized following feed table —
  the feed tool derives from follow edges + authored content (see T-207).
- There is **no root Cargo workspace**; `ansible_rust_core` is a standalone
  crate. `ansible_mcp` will also be standalone (decision D-1 below).
- Settings UI pattern: `ansible_node/app/lib/screens/settings_home_screen.dart`
  + `.panels.dart` / `.rows.dart` companions; services live in
  `ansible_node/app/lib/services/`.

## Decisions

- **D-1 Standalone crate, no workspace.** Adding a root `Cargo.toml` workspace
  would perturb `ansible_rust_core`'s flutter_rust_bridge build. `ansible_mcp/`
  sits at the repo root as its own crate, like `ansible_rust_core`.
- **D-2 `rusqlite` with `bundled` feature.** Pins a known SQLite build across
  macOS/Linux/Windows instead of trusting the system library; opened with
  `OpenFlags::SQLITE_OPEN_READ_ONLY` (WAL read works because the app's writer
  keeps the WAL file; the binary never checkpoints).
- **D-3 `rmcp` (official Rust MCP SDK), stdio transport only.** Pin the latest
  release at implementation time; `transport-io` feature, tools declared with
  `readOnlyHint: true` annotations.
- **D-4 Data-dir discovery is explicit-first.** The Settings screen generates
  the client config snippet with `--data-dir <absolute path>` baked in (the
  app knows the real path). Fallback resolution (`ANSIBLE_MCP_DATA_DIR` env,
  then platform app-support conventions) exists only for `doctor` ergonomics.
- **D-5 Local author DIDs come from the grant file.** The app writes
  `local_author_dids` into `mcp_access_grant.json` at enable time so the
  binary never reads the hard-excluded `identities` table (spec updated
  accordingly).
- **D-6 Feed = derivation, not projection.** `get_follow_feed` resolves
  accepted outbound follow edges to author DIDs / board ids, then reads
  allowlisted content by those authors/boards, reverse-chronological. If a
  materialized `FollowFeedSource` projection lands later (per the 2026-06-04
  feed specs), swap the query, keep the tool contract.

## Phase 1 — Crate skeleton, fail-closed core

Goal: a binary that speaks MCP over stdio, refuses everything without a valid
grant, and can diagnose its own setup. **AC-1, AC-3 land here.**

- [x] **T-101** Create `ansible_mcp/` crate: `rmcp`, `rusqlite` (bundled),
  `serde`/`serde_json`, `clap` (derive), `anyhow`, `time`. Binary target
  `ansible-mcp` with subcommands: `serve` (default) and `doctor`.
- [x] **T-102** `grant.rs`: load + validate `mcp_access_grant.json` from the
  data dir. Struct per the spec (`grant_id`, `created_at`, `expires_at`,
  `local_author_dids`, `scopes{boards, include_murmurs, include_follow_feed}`).
  Missing/expired/malformed ⇒ typed `GrantError`; unknown JSON fields
  tolerated (forward compat). Grant is re-read (cheap stat + mtime check) on
  every tool call so in-app revocation is immediate.
- [x] **T-103** `db.rs`: open `<data-dir>/ansible.db` read-only. Guard chain,
  each failing closed with an actionable message: file exists → readable →
  `PRAGMA user_version` ≤ `MAX_SUPPORTED_SCHEMA` (const, starts at 26; bump
  requires reviewing every query against the migration) → allowlisted tables
  present. Mirrors the app's `DatabaseDowngradeError` posture.
- [x] **T-104** MCP server scaffolding: initialize handshake, server info,
  single tool `get_access_scope` returning scopes, expiry, schema version,
  and DB mtime as "last sync freshness". Wire the fail-closed path: with no
  grant the server still starts and lists tools, but every call returns the
  structured denial (so AI clients show a useful message instead of a spawn
  failure).
- [x] **T-105** `doctor` subcommand: prints data-dir resolution, DB
  found/readable, `user_version` vs supported, WAL present, grant status and
  expiry, audit-log path — exit code 0/1. No content output.
- [x] **T-106** Unit tests: grant parsing/expiry/revocation-by-deletion;
  schema guard against fixture DBs (empty, v26 subset, `user_version` = 99).
  Fixture DB built in-test from a checked-in DDL snippet matching the drift
  snake_case schema subset (boards/threads/posts/content_items/…).

## Phase 2 — Read tools, provenance, audit

Goal: the eight spec tools against a real synced DB. **AC-2, AC-4 land here.**

- [x] **T-201** `queries.rs`: the single allowlist module. Const table +
  column allowlists; every SQL string lives here as a prepared statement.
  Scope filtering (`boards: all | [ids]`) is applied inside each query, never
  post-hoc in the tool layer.
- [x] **T-202** Shared response envelope: `{ author_did, author_display,
  created_at (RFC3339 from epoch), signature_verified, origin_host,
  host_compliance: "unknown", content }` + the untrusted-content notice in
  every tool description (spec wording).
- [x] **T-203** `list_boards` (granted, `is_deleted = 0`) and `list_threads`
  (keyset cursor on `(updated_at, thread_id)`, reverse-chron, default limit
  50 / max 200).
- [x] **T-204** `get_thread`: thread row + flat post list (`parent_post_id`
  included so the client model reconstructs the tree), `is_deleted` filtered,
  hard cap with continuation cursor for very long threads.
- [x] **T-205** `search_content`: `LIKE` with `ESCAPE '\'` (escape `% _ \` in
  the user query) across granted `posts.content`, `threads.title`, and — when
  murmurs are in scope — `content_items.title/body`; returns ±160-char
  snippets around the first match, not full bodies; limit 25.
- [x] **T-206** `get_author`: `contact_records` (`subject_did`, `handle`,
  `display_name`, `avatar_url` — **`local_alias` explicitly not selected**)
  LEFT JOIN `did_reputations` tier.
- [x] **T-207** `get_follow_feed` per D-6: gated on `include_follow_feed`;
  follow edges with `direction = outbound`/`status = accepted` (verify exact
  enum strings against `follow_edge.dart` at implementation) → authored
  posts + public/unlisted content_items, reverse-chron keyset cursor.
- [x] **T-208** `get_murmurs`: gated on `include_murmurs`;
  `mode IN ('murmur','note')`; exclude `visibility = 'private'` and
  `local_only = 1` **unless** `author_did` ∈ grant `local_author_dids`.
- [x] **T-209** `audit.rs`: append-only `mcp_access_audit.log` (JSON lines:
  ts, grant_id, tool, scope args — board/thread ids only — row count). A
  failed audit write fails the tool call (no unaudited reads). Rotate at 5 MB
  (single `.1` backup).
- [x] **T-210** Integration test: spawn the binary, drive a real MCP
  initialize + tool-call session over stdio against a fixture DB; assert the
  denial path (no grant), the scope filter (board not in grant is invisible
  through **every** tool including search), and the private-content exclusion
  (other author's `private`/`local_only` murmur never returned). These three
  assertions are the compliance tests for AC-1/AC-2 and Base Rule 2.

## Phase 3 — Flutter Settings surface

Goal: the consent UX that makes the grant real. Desktop-gated
(`Platform.isMacOS || isLinux || isWindows`).

- [x] **T-301** `services/local_ai_access_service.dart`: create grant (uuid,
  90-day expiry, scopes, `local_author_dids` from the canonical identity
  store), renew, revoke (delete file), read status + tail of audit log.
  Writes atomically (temp file + rename) next to `ansible.db`.
- [x] **T-302** Settings → new "Local AI Access" panel following the
  `settings_home_screen.panels.dart` pattern: disclosure copy (spec wording —
  names the cloud-vendor consequence), scope pickers (board multi-select
  defaulting to subscribed boards, murmur toggle off, follow-feed toggle
  off), enable/renew/revoke.
- [x] **T-303** Client setup card: rendered config snippets for Claude
  Desktop (`claude_desktop_config.json`), Claude Code (`claude mcp add`), and
  a generic stdio JSON block — each with the absolute `--data-dir` baked in
  (D-4), plus a "recent access" list from the audit log.
- [x] **T-304** Widget tests: panel hidden on non-desktop; revoke deletes the
  file; grant JSON matches the spec schema (golden test so spec drift is
  caught).
- [x] **T-305** l10n for the new strings (`ansible_node/app/lib/l10n`),
  zh-Hant + en at minimum, matching existing app conventions.

## Phase 4 — Packaging, docs, real-client verification

- [x] **T-401** Bundle `ansible-mcp` in desktop app packaging (working
  assumption from the spec's open question); `Makefile` /
  `ansible_cli/scripts/build_all.sh` target `build_mcp` producing the binary
  per platform. Settings snippet points at the bundled path.
- [x] **T-402** `ansible_mcp/README.md`: manual setup, doctor usage,
  troubleshooting (schema-newer-than-binary, grant expired, DB not found),
  and the security model in one paragraph.
- [ ] **T-403** Manual verification with Claude Desktop and Claude Code
  against a synced dev node: summarize-a-board, search, thread Q&A; confirm
  revoke-while-connected denies the next call. Record results in this plan.
  *(Pending — needs a human with a synced node. The automated equivalent —
  full MCP session over stdio, revocation mid-session, scope/privacy
  assertions — is covered by `tests/integration_stdio.rs`, 5 tests passing
  2026-07-14.)*
- [x] **T-404** Update `docs/ROADMAP.md` (P3 row → in progress, link this
  plan) and tick the delivered Phase 3 boxes in the backlog TODO.
- [x] **T-405** Add verification commands below to CI where the repo already
  runs Rust tests (or note as local-only if `ansible_rust_core` isn't in CI —
  match existing practice).

## Follow-ups deliberately out of this plan

- FTS5 index + semantic search over `murmur_embeddings` (spec Phase B).
- In-app Streamable-HTTP server, write/draft tools, per-action confirmation
  (spec Phase C — requires its own spec + Constitution Review).
- Per-client grants / tokens (folds into Phase C's token model).
- Persisted `host_compliance` (owned by the external-host-compliance gap in
  the 2026-05-24 compliance review; AC-4's `"unknown"` stands until then).

## Verification Commands

- `cargo test --manifest-path ansible_mcp/Cargo.toml`
- `cargo clippy --manifest-path ansible_mcp/Cargo.toml -- -D warnings`
- `printf '{"jsonrpc":"2.0","id":1,"method":"initialize", ...}' | ansible-mcp serve --data-dir <fixture>` (smoke; scripted in the integration test)
- `ansible-mcp doctor --data-dir <fixture>`
- `flutter test test/local_ai_access_service_test.dart test/settings_local_ai_access_test.dart` (in `ansible_node/app`)
- `flutter analyze lib/services/local_ai_access_service.dart lib/screens/settings_home_screen.dart`

## Risks

- **Drift schema drift.** Any store migration ≥ 27 silently invalidates the
  binary's queries → mitigated by the `MAX_SUPPORTED_SCHEMA` fail-closed guard
  (T-103) and the golden grant/schema tests; bumping the const is a reviewed
  act, and bundling (T-401) keeps app + binary versions in lockstep.
- **`rmcp` API churn.** The SDK is young; pin exact version, isolate it
  behind a thin `server.rs` so a bump touches one file.
- **WAL edge case.** A reader can't open WAL if it lacks write permission to
  create `-shm`; the app always runs first and creates it, but `doctor`
  checks for it explicitly (T-105) so the failure is diagnosable.
- **Enum string drift** (`follow_edges.status/direction`, `content_items.mode`)
  — T-207/T-208 verify exact strings against the Dart entities at
  implementation time; fixture DDL is generated from those files, not by hand.
