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
- [ ] Add entities and repository interfaces. (Entities complete; repository
  interfaces are still pending.)
- [ ] Add Drift and in-memory repositories.
- [x] Add schema migration and generated Drift code.
- [ ] Add store tests for mode queries, lineage, transformations, and privacy
  defaults.

## Phase 2: Manual Product Flows

- [ ] Add manual Murmur -> Note transformation.
- [ ] Add manual Note -> Discussion projection.
- [ ] Add local lineage inspector query/projector.
- [ ] Keep legacy board/thread/post forum behavior working.
- [ ] Add tests for projection acknowledgement and relation creation.

## Phase 3: AI Assistance Foundation

- [ ] Add `AiProvider` interface.
- [ ] Add manual provider for deterministic tests and no-AI fallback.
- [ ] Add OpenAI-compatible provider adapter.
- [ ] Add local HTTP provider adapter for LAN/self-hosted models.
- [ ] Store API keys in Keychain with `flutter_secure_storage`.
- [ ] Add privacy policy checks for remote provider calls.
- [ ] Add context pack builders for transformation and summary tasks.
- [ ] Add summary job storage and save-as-note behavior.

## Phase 4: Low-Friction Flutter UI

- [ ] Add first-use AI provider setup sheet.
- [ ] Return to the original action after provider setup succeeds.
- [ ] Add source-boundary disclosure before remote private-content calls.
- [ ] Add transformation review sheet.
- [ ] Add summary review sheet.
- [ ] Add Murmur screen with 500-character limit.
- [ ] Add Note workspace with linked murmur panel.
- [ ] Add Discussion detail summary action.
- [ ] Add phone-safe navigation for Murmur, Notes, and Discussions.

## Phase 5: Public Sync

- [ ] Add Lexicon record classes for new `io.trisaura.*` content records.
- [ ] Add relay validation for collection/type matching.
- [ ] Add relay validation for required fields.
- [ ] Reject private-only fields from public records.
- [ ] Sync public discussions and public lineage only.
- [ ] Keep private murmurs, private notes, context packs, and summary jobs
  local-only by default.

## Phase 6: Integration And QA

- [ ] Test Murmur -> Note -> Discussion end-to-end.
- [ ] Test Discussion summary -> private note.
- [ ] Test Following or board digest with bounded context.
- [ ] Test remote provider privacy rejection and explicit consent.
- [ ] Run store, domain, vc, app, and relay test suites.
- [ ] Re-test iPhone compact layout after adding mode navigation.

## Decisions Captured

- [x] Use `note` as the Ansible product term for Aleth's `idea`.
- [x] Keep murmurs private/local-only in MVP.
- [x] Use enriched `io.trisaura.post` for structured discussion replies in MVP.
- [x] Store provider secrets in Keychain, never Drift.
- [x] Make manual transformation work without AI.
- [x] Make AI output review-only until the user accepts it.
