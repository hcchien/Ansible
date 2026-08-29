# Elix Deliberation And User-Directed Analysis

> Status: Phase 1 implemented; deterministic projection and stable clustering remain planned
> Date: 2026-08-29
> Scope: Forum Host, Board Access Policy, Flutter mobile/desktop, Web,
> local MCP, analysis snapshots, and deliberation export

## Goal

Add a Board-owned deliberation space inspired by the interaction model of
Polis without copying the Polis implementation or turning the existing
single-question poll into a multi-purpose data model.

A deliberation has one topic and many participant-authored statements.
Participants respond to each statement with `agree`, `disagree`, or `pass`.
Elix publishes reproducible summaries of consensus and disagreement and lets
an authorized user explicitly export a privacy-reduced dataset to the local
read-only MCP server for alternative analysis.

## Product Boundaries

`poll` and `deliberation` remain separate products:

- A poll is one question with a fixed set of mutually exclusive options.
- A deliberation is one topic with many independently evaluated statements.
- A Board may contain any number of threads, polls, and deliberations.
- A Board feed may display a deliberation card, but the canonical
  deliberation is a Forum Host resource rather than a thread payload.
- A discussion thread may link to a deliberation, but neither resource owns or
  silently mutates the other.

The first-party implementation is independently written. No Polis source code
or UI is copied into this repository.

## Constitution Review

This design touches identity, storage, verification, moderation, ranking,
community governance, credentials, Forum Host, AppView, and AI-service data
boundaries. The engineering constitution applies.

1. **Identity and credentials.** Writes are authorized by the participant's
   DID-signed intent or an app-approved Web session. A credential-gated Board
   uses the existing holder-bound, short-lived Board capability. Vote rows do
   not contain the presented VC or its claims.
2. **Data leaving the device.** A vote leaves the device only when the user
   participates in the named deliberation. An MCP export leaves the Forum Host
   and becomes available to a local AI client only after a separate, explicit
   in-app export action that discloses that a cloud-backed client may forward
   the data to its vendor.
3. **Minimum claims.** Forum Host needs only the authorization outcome, Board
   capability scope, DID signature provenance, and a deliberation-scoped
   participant pseudonym. It does not need raw credential claims.
4. **Raw identity exclusion.** Legal identity, provider assertions,
   personhood commitments, biometrics, private keys, VC payloads, DID values,
   exact vote timestamps, IP addresses, and device identifiers are excluded
   from analysis snapshots and MCP exports.
5. **Trust, ranking, and moderation.** Deliberation participation and cluster
   membership never alter trust tier, global ranking, access, or profile
   labels. Statement moderation is host-local, reason-coded, and visible to
   the affected participant.
6. **Personhood.** This feature creates no new personhood binding. If a Board
   already requires a high-assurance credential, the feature consumes only
   the Board capability created by that existing verification path.
7. **Exit and deletion.** A participant can revise or withdraw a response and
   withdraw their statement subject to the visible host retention policy.
   MCP grants and cached exports are revocable and expire. The UI states that
   data already returned to an AI client cannot be recalled.
8. **External hosts.** The client shows host compliance provenance. Unknown or
   unsupported hosts do not receive a first-party analysis or export trust
   assumption.

This design is constitution-compliant if the raw vote matrix remains inside
the Forum Host boundary by default, exports require both Board authorization
and participant-visible export policy, and cluster results are never reused as
identity, trust, moderation, or ranking signals.

## Board Authorization

Every operation inherits the containing Board's current policy:

| Operation | Board action |
|---|---|
| discover/list deliberations | `read` |
| read topic, statements, and published report | `read` |
| vote or submit a statement | `post` |
| create a deliberation | `deliberation_creation` role in posting policy |
| freeze, publish, archive, or moderate | `moderate` |
| MCP published report and aggregate export | `read` |
| MCP pseudonymous response export | `analyze` |

Board Access Policy v2 adds the `analyze` action. For v1 policies,
published/aggregate reads follow `read` and pseudonymous response export fails
closed except for a Board moderator. The default v2 `analyze` requirement is
`board_moderator`; an owner may explicitly assign the same credential
requirement used by `post`.

Capability expiry or policy revocation prevents future reads and writes. It
does not erase a previously accepted response. Each response and analysis
snapshot records the applicable access-policy version so a policy transition
is visible rather than silently rewriting history.

## Deliberation Export Policy

At creation the host records one immutable-widening export mode:

- `no_external_analysis`
- `aggregates_only` (default)
- `pseudonymous_matrix`

Before the first vote the UI shows the selected mode. After the first vote the
mode may only become more restrictive. It cannot be widened without creating
a new deliberation and collecting new consent.

Board `analyze` authorization and deliberation export mode are independent and
both are required. A moderator cannot override a participant-visible
`aggregates_only` or `no_external_analysis` promise.

## Forum Host Data Model

### `forum_host_deliberations`

- canonical UUID `id`
- `hosted_board_id`
- `title`, `prompt`, and optional `context`
- `status`: `collecting`, `frozen`, `published`, `archived`
- `statement_attribution`: first release uses `host_pseudonymous`
- `export_mode`
- privacy thresholds and optional `closes_at`
- creator DID retained only for authorization/governance
- policy version, inserted/updated timestamps

### `forum_host_deliberation_statements`

- canonical UUID `id` and `deliberation_id`
- statement text
- author participant key and restricted author DID
- `pending`, `accepted`, `rejected`, or `withdrawn`
- moderation reason code
- timestamps

Public and export responses omit the author DID and exact moderation actor.

### `forum_host_deliberation_votes`

- `deliberation_id`, `statement_id`
- domain-separated `participant_key`
- `agree`, `disagree`, or `pass`
- `last_intent_id` and access-policy version
- timestamps retained at the host but excluded from analysis/export rows
- unique `(deliberation_id, statement_id, participant_key)`

The participant key is an HMAC over host identity, deliberation id, and DID
using a versioned secret. A plain hash is not sufficient. It must not be
returned by an API.

Vote changes use optimistic concurrency: an update or withdrawal names the
current `supersedes_intent_id`. A stale intent fails with a reason-coded
conflict rather than overwriting a newer response.

### `forum_host_deliberation_analysis_snapshots`

- input high-water mark and dataset digest
- algorithm name/version/seed/parameters
- participant, statement, and response counts
- statement aggregates, consensus, disagreement, and optional clusters
- privacy-suppression reasons
- generated timestamp and status

Identical input, version, parameters, and seed must produce the same snapshot.
An algorithm upgrade creates a new snapshot and never rewrites an old report.

### Durable analysis jobs

Analysis is not run in an HTTP request. A PostgreSQL-backed job row is claimed
transactionally so Cloud Run termination or multiple instances cannot lose or
duplicate work. The analyzer is behind a versioned behavior and may use a
dirty-CPU Rust NIF while keeping the input inside the Forum Host process.

## Analysis Contract

The analyzer receives accepted statements and the sparse response matrix while
retaining the distinction between `pass` and missing. It produces:

- per-statement agree/disagree/pass counts and coverage;
- consensus and disagreement rankings with per-group rates;
- a deterministic low-dimensional projection;
- two to five candidate clusters selected only when stability and minimum
  group-size rules pass;
- an explicit `insufficient_stable_structure` result instead of forced
  clusters.

The first release may publish aggregates before clustering is enabled, but the
UI and API must label which analysis capabilities the snapshot contains. It
must never imply that a preliminary aggregate report is a completed cluster
analysis.

## Privacy Thresholds

Initial defaults, versioned in the deliberation:

- fewer than 15 participants: no cluster report;
- group smaller than 5: suppress or merge the group;
- statement below minimum response coverage: exclude it from rankings;
- pseudonymous matrix export: require at least the configured export minimum;
- no raw matrix, participant key, DID, exact vote time, VC claim, IP, or device
  information in logs, metrics, snapshots, AppView, Relay delta, Nostr, or
  ActivityPub.

These thresholds may be made stricter after voting begins, never weaker.

## API Contract

Read endpoints require Board `read`; writes accept the existing Web-session
or signed-intent rails and enforce current Board capability requirements.

```text
GET    /api/v1/forum-host/boards/:board_id/deliberations
POST   /api/v1/forum-host/boards/:board_id/deliberations
GET    /api/v1/forum-host/boards/:board_id/deliberations/:id
POST   /api/v1/forum-host/boards/:board_id/deliberations/:id/statements
PUT    /api/v1/forum-host/boards/:board_id/deliberations/:id/statements/:statement_id/vote
DELETE /api/v1/forum-host/boards/:board_id/deliberations/:id/statements/:statement_id/vote
POST   /api/v1/forum-host/boards/:board_id/deliberations/:id/responses/mine
POST   /api/v1/forum-host/boards/:board_id/deliberations/:id/manage
GET    /api/v1/forum-host/boards/:board_id/deliberations/:id/report
POST   /api/v1/forum-host/boards/:board_id/deliberations/:id/exports
```

Signed intent types are independently versioned:

- `io.trisaura.forum.createDeliberation`
- `io.trisaura.forum.submitDeliberationStatement`
- `io.trisaura.forum.castDeliberationVote`
- `io.trisaura.forum.withdrawDeliberationVote`
- `io.trisaura.forum.readDeliberationResponses`
- `io.trisaura.forum.exportDeliberation`
- `io.trisaura.forum.manageDeliberation`

## Client Behavior

Flutter mobile and desktop share the same models, Forum Host client, and
responsive screens. Web uses the same HTTP contract and approved Web session.

Every supported client provides:

- a Board-level Deliberations section;
- creation UI when authorized;
- statement-card participation with agree/disagree/pass;
- current response revision/withdrawal;
- statement submission;
- aggregate/report view with method and privacy explanations;
- explicit export-policy disclosure before first participation;
- an export action when authorized.

Small screens use one statement card at a time. Desktop and Web may add a
statement navigator and report rail, but must preserve identical semantics.

## Local MCP Export

The existing `ansible-mcp` remains local, read-only, networkless, and backed by
an explicit expiring grant. It never receives a Board capability or accesses
Wallet tables.

Export flow:

1. User selects **Make available to Local AI** in the app.
2. The app re-authorizes the current Board action and obtains a fixed export
   snapshot from Forum Host.
3. Forum Host removes prohibited fields and rekeys participant ids for the
   export/snapshot so they cannot be correlated with host participant keys.
4. The app writes the export into new allowlisted local tables with a short
   expiry and manifest digest.
5. The cached row itself is the per-deliberation/view grant: MCP additionally
   requires that its Board is inside the current Local AI Board scope. Merely
   reading or participating never creates this row.
6. MCP serves only an unexpired cached export and records metadata-only audit
   entries. Deleting the row, narrowing the Board scope, or revoking the Local
   AI grant independently stops future reads.

Tools:

- `list_deliberations`
- `get_deliberation`
- `get_deliberation_report`
- `get_deliberation_dataset_manifest`
- `list_deliberation_statements`
- `list_deliberation_responses`

The current Phase 1 cache is a bounded, fixed snapshot and returns that
snapshot as a whole. Cursor pagination is required before raising the export
threshold or supporting large matrices. There is no raw-SQL or arbitrary-file tool.
The UI states that revoking the grant cannot recall data already returned to an
AI client.

## Phase 1 Implementation Slice

The implemented vertical slice includes the Forum Host schema and signed/Web
APIs, Board-aware Flutter mobile/desktop and Web participation, aggregate
consensus/disagreement reports, explicit privacy-bounded exports, the local
Drift export cache, and read-only MCP tools. The built-in analyzer currently
publishes deterministic statement-level aggregates only and labels the result
`aggregate_only`.

Durable analysis jobs, low-dimensional projection, cluster stability scoring,
per-group rates, moderation management UI, federation/AppView projection, and
large-export cursor pagination remain follow-up phases. Until those land, no
client may describe the aggregate report as Polis-style participant grouping
or completed cluster analysis.

## Federation And AppView

The first release does not project raw votes, participant rows, or analysis
inputs into AppView or federation. A public deliberation card or a signed
published aggregate snapshot may be added later through a separate projection
contract. Private or credential-gated deliberations have no public fallback.

## Verification

- migrations and Ecto schema constraints;
- signed intent canonicalization, expiry, replay, and optimistic concurrency;
- Board v1/v2 read/post/moderate/analyze and VC-capability coverage;
- cross-Board and cross-deliberation participant-key separation;
- aggregate determinism and privacy thresholds;
- public delta/AppView/federation negative leakage tests;
- Flutter model/client/widget tests on narrow and wide layouts;
- Web renderer, session, error, and interaction tests;
- MCP grant, allowlist, pagination, expiry, audit, and cross-scope tests;
- end-to-end run with several identities and a credential-gated Board.

## Rollout

Ship behind a Forum Host capability and client feature flag. Migrate and verify
the development Forum Host first, run an internal Board pilot, then deploy the
production migration before the production service revision. Only after the
production APIs are verified should a mobile/desktop release be built and
uploaded. Deployment, TestFlight upload, review submission, and end-user
availability are separate completion boundaries.
