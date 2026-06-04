# Following Feed — Murmur/Note Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give followed users' **standalone short-form content** — `murmur` (io.trisaura.murmur) and `note` (io.trisaura.note) — a following feed (a timeline), the same way board posts get one. Today murmur/note are fully modeled and stored locally, publishable to Nostr, but they **never traverse the relay ops layer**, so no other user can receive them and there is no timeline of a followed user's murmurs/notes.

**Companion to:** `docs/superpowers/plans/2026-06-04-following-feed-author-sync.md` (board-post following feed). That plan adds the **followed-author retention gate** to `RemoteSyncService` (keep ops whose `author_did` ∈ followed users). This plan **depends on that gate** and extends it to a new op kind plus a new projector. Implement the board-post plan's Task 1 first (or in the same effort).

**Transport decision:** Route **public** murmur/note through **relay ops** (unified path). Chosen over Nostr-fetch and atproto-repo paths because the outbound op pipeline and the followed-author delta gate already exist and are generic — murmur/note become two new `entity_type`s and ride the same global delta, reusing verification, the follow-graph-privacy property, and the gate. Nostr publication stays as an additional, parallel distribution path (unchanged).

## Source Context

Read first:

- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
- Constitution compliance review: `docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`
- Companion plan: `docs/superpowers/plans/2026-06-04-following-feed-author-sync.md`
- Content lineage lexicon: `docs/protocol/tris_aura_content_lineage_lexicon_v0.1.md`

Key existing code (all verified present):

- **Outbound op pipeline is generic for any entity_type:**
  - `ansible_node/app/lib/services/ops_dispatch_service.dart` — `signAndEnqueue` / `sign` (Ed25519 via `DidSigner`)
  - `ansible_node/app/lib/services/op_signature_payload.dart` — `OpSignaturePayload.fromFields(opId, authorDid, entityType, entityId, opType, payload)` canonical JSON
  - `ansible_node/app/lib/services/relay_ops_client.dart` — `ingest()` → `POST /api/v1/ops`
  - `ansible_core/store/lib/src/crdt/crdt_op_builder.dart` — `createBoard/createThread/createPost/createReaction` (NO murmur/note yet)
- **ContentItem model + repo (ready):**
  - `ansible_core/store/lib/src/entities/content_item.dart` — `ContentItem{ id, authorDid, mode, body, status, visibility(private|unlisted|public), title?, publishedAt?, localOnly, isDeleted, ... }`
  - `ansible_core/store/lib/src/schema/content_metadata.dart` — `MurmurMetadata{ tone, sourceType, privateTagsJson, isSensitive }`, `NoteMetadata{ thesis, outlineJson, summary, ... }`
  - `ansible_core/store/lib/src/repositories/content_item_repository.dart` — `list({ContentMode? mode, String? authorDid})`, `getById/create/update/delete`; Drift + in-memory impls exist
- **Relay:**
  - `ansible_relay/phoenix/lib/ansible_relay/web/controllers/ops_controller.ex` — `@valid_entity_types ~w(board thread post reaction)` (NO murmur/note), generic `signing_payload`/`canonical_json`
  - `xrpc_controller.ex` — already validates `io.trisaura.murmur` (`text`, `createdAt`) and `io.trisaura.note` (`body`, `visibility`, `createdAt`)
- **Privacy enforcement (reuse):** `ansible_node/app/lib/services/content_publication_service.dart` rejects `visibility == private || localOnly`; `ansible_core/nostr/.../nostr_content_projection.dart` `_ensureDistributable`
- **Feed (post-only today):** `ansible_core/domain/lib/src/follow/follow_feed_projector.dart`; UI `FeedFilter{ all, following, boards }` in `ansible_node/app/lib/widgets/feed_filter_tabs.dart`, wired in `home_shell.dart`

---

## Constitution Review

Touches sync, federation, distribution, and content visibility.

1. **Identity involved:** follower `followerDid`, author `authorDid` on each `ContentItem`/op. No Wallet credential or TW digital-identity payloads enter murmur/note ops.
2. **Data leaving device — user-chosen?** Only **public or unlisted** murmur/note are turned into relay ops, and only when the user publishes. `visibility == private` and `localOnly == true` MUST fail closed and never become an op (Base Rule 2). `MurmurMetadata.privateTagsJson` MUST NOT be included in the op payload. Drafts (`status == draft`) are not published.
3. **Minimum claim:** none; content distribution only.
4. **Raw legal identity excluded:** murmur/note payloads carry author DID + authored text/title only.
5. **Trust tier / ranking / moderation:** no global ranking; timeline is a **local projection** with reason codes (`followedUser`). Relay per-DID abuse limits on ingest are preserved. `MurmurMetadata.isSensitive` is carried as a render hint, not a suppression signal.
6. **Personhood / duplicate key:** none.
7. **Exit / revoke:** unfollowing purges that author's follow-only murmur/note locally (Task 6) — mandatory.
8. **External-host compliance:** MVP = first-party DID authors on the Genesis relay; Nostr/AP cross-network ingestion of murmur/note remains separate future work.

**Privacy property (inherited from companion plan):** ingest reuses the **global delta + local author filter** gate, so the relay does not learn the follow graph. **No author-scoped request is introduced.**

**Visibility enforcement is the key new MUST:** public-only relaying is enforced at the app publish boundary (fail-closed), reusing the existing `content_publication_service` checks, with relay-side defense-in-depth in Task 1.

**Verdict:** Compliant, conditional on (a) public-only/`!localOnly` publish gating, (b) excluding `privateTagsJson` from op payloads, and (c) unfollow purge.

---

## Design Decisions

- **Two new op entity_types: `murmur`, `note`.** They are standalone (no board/thread), so unlike board posts they need **no stub board/thread** — they store directly as `ContentItem`s.
- **Reuse the companion plan's followed-author gate.** A murmur/note op has no `boardId`; it is retained purely by the `author_did ∈ followedAuthorDids` condition already added there. This plan adds the **apply** branch (op → `ContentItem`) and the **projector**.
- **Op payload = the distributable subset of the ContentItem**, not the whole row. Include: `mode`, `body`, `title?`, `publishedAt`/`createdAt`, `visibility`, and murmur `tone`/`sourceType`. Exclude `privateTagsJson`, draft state, and any local-only metadata.
- **Separate or merged timeline?** Provide a dedicated murmur/note **timeline projector** (`ContentItemFeedProjector`) returning content-item entries. The UI MAY merge it with the post Following feed or show it as its own filter; this plan keeps the projector separate and adds a UI surface (Task 5) without forcing a merge.
- **Nostr path unchanged.** Publishing also-to-relay-ops is additive; the existing Nostr projection/publish remains.

**Tech stack:** Dart, Flutter, Drift, Elixir (relay), `dart test` / `flutter test` / `mix test`, `dart analyze` / `flutter analyze --no-fatal-infos`.

### Forward-compatibility with the scale design

Per `docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md`,
this plan directly delivers two of the five forward-compat requirements:
**item 2** (murmur/note flow through relay ops with `author_did` + `log_id`) and
**item 5** (op payloads carry `visibility`). The `ContentItemFeedProjector`
(Task 4) must sit behind the `FollowFeedSource` interface from the board-post
plan's Task 7 so the AppView `AppViewTimelineSource` can later serve murmur/note
timelines too.

---

## Task 1: Relay accepts murmur/note ops (public-only)

**Files:**
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/ops_controller.ex`
- Test: `ansible_relay/phoenix/test/.../ops_controller_test.exs` (extend / create)

- [ ] **Step 1: Failing test.** POST `/api/v1/ops` with `entity_type: "murmur"` (valid sig, verified DID) → currently `422 invalid_value`. Add tests asserting `202` for `murmur` and `note`, and that a `note` op whose decoded `payload.visibility == "private"` is rejected `422`.
- [ ] **Step 2: Add entity types.** `@valid_entity_types ~w(board thread post reaction murmur note)`.
- [ ] **Step 3: Defense-in-depth visibility check.** For `entity_type in ["murmur","note"]`, decode the `payload` JSON; if it parses and contains `"visibility"` equal to `"private"` (or, for murmur, an explicit private marker), reject `422 {error: "private_content_not_relayable"}`. Do not log payload contents. (Primary enforcement is app-side; this is a backstop.)
- [ ] **Step 4: Confirm signing path unchanged.** `signing_payload`/`canonical_json` already generic — no change. Op stored via existing `OpStore.append`.
- [ ] **Step 5: `mix test` green. Commit** `feat(relay): accept public murmur/note ops`.

## Task 2: App publishes public murmur/note as relay ops

**Files:**
- Modify: `ansible_core/store/lib/src/crdt/crdt_op_builder.dart` — add `createMurmur` / `createNote`
- Modify: `ansible_node/app/lib/services/content_publication_service.dart` (or the murmur/note publish trigger) to enqueue an op alongside existing distribution
- Test: `ansible_core/store/test/crdt_op_builder_test.dart`, `ansible_node/app/test/content_op_publish_test.dart`

- [ ] **Step 1: Failing test.** `CrdtOpBuilder.createMurmur(...)` / `createNote(...)` produce an `OpsQueueEntry` with `entityType == 'murmur'|'note'`, `opType == 'insert'`, and a payload containing the distributable subset only (no `privateTagsJson`). Publishing a `public` murmur enqueues exactly one op; publishing a `private` or `localOnly` murmur enqueues **zero** ops.
- [ ] **Step 2: Implement builders.** Mirror `createPost`: build canonical payload JSON (`mode`, `body`, `title?`, `createdAt`/`publishedAt`, `visibility`, murmur `tone`/`sourceType`), set `entityId = contentItem.id`.
- [ ] **Step 3: Wire publish.** Where a murmur/note is published (content_publication_service), after the existing visibility/localOnly fail-closed checks, enqueue the op via `OpsDispatchService.signAndEnqueue`. Reuse existing dispatch/flush — no new client. Idempotent on re-publish (dedupe by op_id/entity).
- [ ] **Step 4: Privacy assertions.** Test that `privateTagsJson` and draft items never reach an op payload.
- [ ] **Step 5: Green + analyze. Commit** `feat(app): publish public murmur/note to relay ops`.

## Task 3: App ingests murmur/note ops into ContentItem store

**Files:**
- Modify: `ansible_node/app/lib/services/remote_sync_service.dart` — route `entity_type` murmur/note in `_applyActivity`; add `_applyContentItemActivity`
- Modify: the Activity/DeltaResponse parsing if it whitelists entity types
- Test: `ansible_node/app/test/remote_sync_murmur_note_test.dart`

- [ ] **Step 1: Failing test.** Global delta contains a `murmur` op authored by a followed user (no board). After `syncFromNode`, a `ContentItem(mode: murmur, authorDid: alice)` exists locally; a murmur by a non-followed author is dropped (retained only via the companion plan's followed-author gate).
- [ ] **Step 2: Ensure the gate keeps them.** Confirm the companion plan's `allowedByFollowedAuthor` condition covers entity types with no board. (No board/thread stub needed — murmur/note are standalone.)
- [ ] **Step 3: Apply branch.** In `_applyActivity`, route `entity_type in {murmur, note}` to `_applyContentItemActivity`, which upserts a `ContentItem` (and murmur/note metadata) from the op payload via `ContentItemRepository`. Verify Ed25519 + DID-key binding is already enforced upstream (`_trustedActivities` / `_opSignatureVerifier`) — reuse, do not weaken.
- [ ] **Step 4: Mark provenance.** Set a flag/source so these remotely-synced, follow-only items can be purged on unfollow (Task 6) and are distinguishable from the user's own authored items.
- [ ] **Step 5: Green + analyze. Commit** `feat(app): ingest followed-users' murmur/note ops`.

## Task 4: ContentItemFeedProjector (murmur/note timeline)

**Files:**
- Create: `ansible_core/domain/lib/src/follow/content_item_feed_projector.dart`
- Modify: `ansible_core/domain/lib/ansible_domain.dart`
- Test: `ansible_core/domain/test/content_item_feed_projector_test.dart`

- [ ] **Step 1: Failing test.** Given followed user `alice` and local `ContentItem`s (her public murmur + note, plus a non-followed author's murmur, plus alice's `private` item), `project(followerDid)` returns alice's public murmur and note only, sorted newest-first, each with reason `followedUser`.
- [ ] **Step 2: Implement.** Model `ContentFeedEntry { ContentItem item; Set<FollowFeedReason> reasons }`. Resolve followed-user DIDs via `followRepository.listFollowing(followerDid, targetType: user)`; query `contentItemRepository.list(mode: murmur/note)` (or list-all then filter by `mode in {murmur,note}`), keep items whose `authorDid` ∈ followed DIDs and `visibility != private` and `!isDeleted`; sort by `publishedAt ?? createdAt` desc.
- [ ] **Step 3: Export + green + analyze. Commit** `feat(domain): murmur/note following timeline projector`.

## Task 5: UI — followed murmur/note timeline

**Files:**
- Modify: `ansible_node/app/lib/widgets/feed_filter_tabs.dart` and/or `home_shell.dart`
- Test: `ansible_node/app/test/following_timeline_test.dart`

- [ ] **Step 1: Surface the timeline.** Add a way to view the murmur/note following timeline — either a new `FeedFilter` segment (e.g. `timeline`) or a section within the Following view — built from `ContentItemFeedProjector`.
- [ ] **Step 2: Provenance + render.** Each entry shows author + "FOLLOWING" provenance and a murmur-vs-note visual distinction; honor `isSensitive` as a render hint (e.g. collapsed/blurred), not removal. No board context required.
- [ ] **Step 3: Widget test + `flutter analyze --no-fatal-infos`. Commit** `feat(app): followed murmur/note timeline UI`.

## Task 6: Unfollow purges followed-author murmur/note (exit requirement)

**Files:**
- Modify: `ansible_core/domain/lib/src/follow/follow_service.dart` (`unfollow` user path)
- Test: `ansible_core/domain/test/follow_service_test.dart` (extend)

- [ ] **Step 1: Failing test.** After following alice and ingesting her murmur/note, `unfollow` deletes her follow-only `ContentItem`s (those marked remotely-synced in Task 3 Step 4) while keeping the user's own authored items and anything justified by another retained relationship.
- [ ] **Step 2: Implement.** Extend the companion plan's unfollow purge to also delete `ContentItem`s where `authorDid == targetDid` AND the item is flagged remotely-synced/follow-only. Reason-code the event.
- [ ] **Step 3: Green + analyze. Commit** `feat: purge followed-user murmur/note on unfollow`.

## Task 7 (optional): AT Protocol record parity

- [ ] Add a Dart service mapping `ContentItem` → `io.trisaura.murmur` / `io.trisaura.note` records and submitting via XRPC `createRecord` (relay already validates these). Keeps the user's atproto repo authoritative in addition to ops. Documentation/optional; not required for the feed.

---

## Definition of Done

- Following a DID-identified user surfaces their **public** murmurs and notes in a timeline (forward sync; backfill shares the companion plan's optional backfill).
- Private / `localOnly` / draft murmur/note never become relay ops; `privateTagsJson` never leaves the device; relay rejects private note payloads as backstop.
- Non-followed authors' murmur/note are excluded; relay learns no follow graph.
- Unfollow purges that author's follow-only murmur/note locally.
- `mix test` / `dart test` / `flutter test` green; analyzers clean.
- Constitution Review above remains accurate after implementation.
```
