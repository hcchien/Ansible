# Content Lineage Transformation And AI Assistance TODO

> Date: 2026-05-06  
> Source specs:
> - `docs/superpowers/specs/2026-05-06-content-lineage-transformation-design.md`
> - `docs/protocol/tris_aura_content_lineage_lexicon_v0.1.md`
> Implementation plan:
> - `docs/superpowers/plans/2026-05-06-content-lineage-transformation-ai.md`

## Phase 1: Local Model

- [x] Add `content_items` and mode metadata Drift tables.
- [x] Add `content_relations`, `transformation_jobs`, `projections`, and
  `ownership_policies`.
- [x] Add `ai_provider_configs`, `context_packs`, and `summary_jobs`.
- [x] Add entities and repository interfaces.
- [x] Add Drift and in-memory repositories.
- [x] Add schema migration and generated Drift code.
- [x] Add store tests for mode queries, lineage, transformations, and privacy
  defaults.

## Phase 2: Manual Product Flows

- [x] Add manual Murmur -> Note transformation.
- [x] Add manual Note -> Discussion projection.
- [x] Add local lineage inspector query/projector.
- [x] Keep legacy board/thread/post forum behavior working.
- [x] Add tests for projection acknowledgement and relation creation.

## Phase 3: AI Assistance Foundation

- [x] Add `AiProvider` interface.
- [x] Add manual provider for deterministic tests and no-AI fallback.
- [x] Add OpenAI-compatible provider adapter.
- [x] Add local HTTP provider adapter for LAN/self-hosted models.
- [x] Store API keys in Keychain with `flutter_secure_storage`.
- [x] Add privacy policy checks for remote provider calls.
- [x] Add context pack builders for transformation and summary tasks.
- [x] Add summary job storage and save-as-note behavior.

## Phase 4: Low-Friction Flutter UI

- [x] Add first-use AI provider setup sheet.
- [x] Return to the original action after provider setup succeeds.
- [x] Add source-boundary disclosure before remote private-content calls.
- [x] Add transformation review sheet.
- [x] Add summary review sheet.
- [x] Add Murmur screen with 500-character limit.
- [x] Add Note workspace with linked murmur panel.
- [x] Add Discussion detail summary action.
- [x] Add phone-safe navigation for Murmur, Notes, and Discussions.

## Phase 5: Public Sync

- [x] Add Lexicon record classes for new `io.trisaura.*` content records.
- [x] Add relay validation for collection/type matching.
- [x] Add relay validation for required fields.
- [x] Reject private-only fields from public records.
- [x] Sync public discussions and public lineage only.
- [x] Keep private murmurs, private notes, context packs, and summary jobs
  local-only by default.

## Phase 6: Integration And QA

- [x] Test Murmur -> Note -> Discussion end-to-end.
- [x] Test Discussion summary -> private note.
- [x] Test Following or board digest with bounded context.
- [x] Test remote provider privacy rejection and explicit consent.
- [x] Run store, domain, vc, app, and relay test suites.
- [x] Re-test iPhone compact layout after adding mode navigation.

## Decisions Captured

- [x] Use `note` as the Ansible product term for Aleth's `idea`.
- [x] Keep murmurs private/local-only in MVP.
- [x] Use enriched `io.trisaura.post` for structured discussion replies in MVP.
- [x] Store provider secrets in Keychain, never Drift.
- [x] Make manual transformation work without AI.
- [x] Make AI output review-only until the user accepts it.
