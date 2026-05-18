# LLM Plugin And MCP Access TODO

> Date: 2026-05-16  
> Source: product backlog discussion  
> Related work:
> - `docs/superpowers/todos/2026-05-06-content-lineage-transformation-ai.md`
> - `docs/superpowers/todos/2026-05-11-app-mediated-web-session.md`
> - `docs/architecture/genesis_hosting.md`

## Goal

Let users connect ChatGPT, Codex, Claude, Claude Code, and other MCP-capable
agents to their Tris-Aura identity and relay subscriptions so the agent can
summarize followed content, analyze subscribed feeds, prepare drafts, and help
with publication workflows without receiving root signing keys or broad account
access.

## Phase 0: Platform Research

- [ ] Track ChatGPT Apps SDK submission requirements, review constraints, and
  directory eligibility.
- [ ] Track Codex plugin publishing status and local/custom marketplace support.
- [ ] Track Claude custom connector, connector directory, and plugin directory
  requirements.
- [ ] Confirm which surfaces support remote MCP, local MCP, OAuth, interactive
  UI, and tool confirmation flows.
- [ ] Keep a short compatibility matrix for ChatGPT, Codex, Claude, Claude Code,
  and local desktop clients.

## Phase 1: Shared Agent Access Contract

- [ ] Define an `AgentAccess` API surface shared by cloud plugins and local MCP.
- [ ] Add read scopes for followed users, subscribed boards, feed windows, and
  identity display.
- [ ] Add draft scopes for AI-generated notes, replies, and post outlines.
- [ ] Keep publication scopes separate from draft scopes.
- [ ] Reuse app-mediated web-session grants for cloud access where possible.
- [ ] Define short TTL, revocation, audit logging, and device/session labels.
- [ ] Ensure agent sessions never expose DID private keys or provider secrets.

## Phase 2: Remote MCP / Cloud Plugin Path

- [ ] Build a hosted remote MCP server backed by relay APIs.
- [ ] Support OAuth or app-mediated DID approval for per-user access.
- [ ] Expose tools for feed summary, followed-author digest, board digest, and
  source lookup.
- [ ] Return only the minimum content needed for the requested summary or
  analysis.
- [ ] Add redaction and source-boundary controls before sending private or
  semi-private context to cloud LLM surfaces.
- [ ] Add review-mode tools that create drafts or publication intents but do not
  publish automatically.
- [ ] Prepare ChatGPT Apps SDK metadata, screenshots, privacy policy, test
  prompts, and review accounts.

## Phase 3: Local MCP / Device-First Path

- [ ] Build a local MCP server that talks to the user's local Ansible node.
- [ ] Let local agents read local cache, followed feeds, subscriptions, and
  drafts without exposing them through the public relay.
- [ ] Keep sensitive content local by default and require explicit user approval
  before any remote model call.
- [ ] Package setup instructions for Claude Desktop, Claude Code, Codex, and
  other local MCP clients.
- [ ] Add a health check and diagnostics command for local MCP setup.
- [ ] Support the same tool names and response schemas as the remote MCP path.

## Phase 4: Write And Publication Guardrails

- [ ] Make the default write path `draft -> user review -> signed publication
  intent -> relay accept`.
- [ ] Require explicit confirmation for every publish, reply, update, or delete
  action in MVP.
- [ ] Show DID, destination, visibility, target board/thread, and final content
  before signing.
- [ ] Add per-tool destructive/write annotations for MCP clients that support
  them.
- [ ] Log agent-assisted publication attempts without logging hidden private
  context.
- [ ] Add rate limits for agent-assisted read and write activity.

## Phase 5: Product Packaging

- [ ] Offer a convenience mode for remote cloud plugins.
- [ ] Offer a privacy mode for local MCP.
- [ ] Offer a hybrid mode where the local node summarizes/redacts before cloud
  LLM analysis.
- [ ] Document user-facing setup and revocation flows.
- [ ] Add admin/workspace notes for organizations that want to restrict agent
  write scopes.
- [ ] Prepare directory submission paths after the MCP server and consent model
  are stable.

## Decisions Captured

- [x] Build both remote/cloud and local/device-first integrations.
- [x] Share one agent-facing API contract across both paths.
- [x] Keep publication gated by explicit user confirmation in MVP.
- [x] Do not give plugins or MCP clients root DID private keys.
- [x] Treat public directory listing as a later distribution step, not as the
  initial dependency for the feature.
