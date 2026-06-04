# Following Feed — Followed-User Post Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the **Following feed actually contain posts from followed users.** Today follows are stored, the feed projector filters local posts by followed-user DID and followed-board id, and board follows pull posts via the relay delta. But following a *user* pulls nothing: the app downloads the global op stream and then **discards** any op whose board is not in the synced set, so a followed user's posts never reach the local store unless they happen to post in a board you already sync.

**Core insight:** The transport already exists. `RemoteSyncService.syncFromNode` pulls the relay's **global** `/api/v1/ops/delta` stream (every op carries `author_did` and a verifiable signature) and drops ops outside the enabled board set (`remote_sync_service.dart` ~L381-388). The MVP fix is to **also keep ops authored by a followed user**, materialise enough local context (board/thread stub) to store and render them, and purge them on unfollow. No new relay endpoint is required for the MVP.

## Source Context

Read first:

- Constitution: `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
- Constitution compliance review: `docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`
- Existing follow infra plan: `docs/superpowers/plans/2026-05-04-follow-users-boards.md`
- Sync spec: `docs/protocol/tris_aura_sync_spec_v2.0.md`

Key existing code:

- App sync + gate: `ansible_node/app/lib/services/remote_sync_service.dart`
  - `syncFromNode` gate at ~L381-388 (`requireBoardSyncConfig`, `enabledBoardIdSet`, `continue`)
  - `_applyActivity` / `_applyThreadActivity` (~L616) / `_applyPostActivity` (~L643) — post/thread require `boardId!` and `threadId!`
  - `_pruneExpiredPosts` (~L529) — only prunes enabled board configs
- Feed projector (already filters by followed-user DID): `ansible_core/domain/lib/src/follow/follow_feed_projector.dart`
- Follow service / unfollow: `ansible_core/domain/lib/src/follow/follow_service.dart`
- Follow repo: `ansible_core/store/lib/src/repositories/follow_repository.dart` (`listFollowing(followerDid, targetType: user)`)
- Relay op model (already indexed-able by author): `ansible_relay/phoenix/lib/ansible_relay/db/op.ex`, ingestion/delta: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/ops_controller.ex`

---

## Constitution Review

This feature touches sync, federation, and distribution, so it is evaluated against the engineering constitution.

1. **User-controlled identity/credential involved:** The follower's `followerDid` and the followed user's `author_did`. No Wallet credential payloads or Taiwan digital-identity assertions are involved — follow is social subscription state only (existing boundary, reaffirmed).
2. **What data leaves the device, did the user choose it?** Only **public ops** already published to the relay are pulled. Following a user is an explicit, user-initiated subscription (a `FollowEdge`). No private content is fetched or sent — private content stays local and fail-closed (Base Rule 2). The relay never receives private data as part of this feature.
3. **Minimum claim:** None. This is content distribution, not verification. No verification claim is presented.
4. **Raw legal identity excluded:** Ops carry `author_did` + post content only. No passport/national-id/legal-name/provider-assertion fields are introduced into payloads, logs, or feed entries.
5. **Trust tier / ranking / moderation change:** No global ranking. The feed is a **local projection** with reason codes already present (`FollowFeedReason.followedUser` / `followedBoard`). No new system-level suppression. Existing per-DID abuse rate limiting on the relay is preserved (Base Rule 4 / 7).
6. **Personhood binding / duplicate key:** None created.
7. **Exit / revoke:** Unfollowing a user MUST stop syncing their posts and MUST purge locally-synced posts that are only present because of that follow (Task 3). Users keep full local control (Base Rule 1 / 2).
8. **External-host compliance:** MVP scopes to first-party DID-identified authors on the Genesis relay. Remote ActivityPub-actor post ingestion is out of MVP scope and is noted as future work; when added it MUST carry the source host's compliance level.

**Privacy trade-off (documented, per checklist Q2/Q8):** MVP **Design 1** uses the existing global delta and filters locally, so the relay does **not** learn which authors a user follows — there is no per-author request that would leak the follow graph. The alternative **Design 2** (author-scoped relay delta) is more bandwidth-efficient and enables targeted backfill, but it reveals a user's follow set to the relay. Design 2 is therefore deferred and, if adopted, MUST be accompanied by a follow-graph-leak mitigation (batching/padding, or AppView-side privacy). This plan implements Design 1.

**Constitution verdict:** Compliant. No MUST/MUST NOT rule is violated. The exit-and-purge requirement (Task 3) is mandatory for compliance.

---

## Design Decisions

- **Design 1 (this plan, MVP): local-filter over the existing global delta.** Keep ops whose `author_did` ∈ followed-user DIDs in addition to enabled-board ops. Zero new relay surface, no follow-graph leak, ~zero extra bandwidth (the app already downloads these ops, it just discarded them).
  - *Limitation — backfill:* a newly-followed author's posts older than the app's current global sync cursor are not retroactively pulled by normal forward sync. The Following feed shows their posts **going forward** plus anything already local. Optional Task 5 adds a bounded one-time backfill rescan.
  - *Limitation — context:* a followed user's reply may live in a thread/board authored by others and not synced locally. The app creates a **stub board + thread** (placeholder title) so the post is storable and renderable. Titles backfill if the real thread op later arrives.
  - *Scope:* followed users identified by **DID** (first-party network). Remote ActivityPub-actor outbox ingestion is out of scope.
- **Design 2 (future / scale): author-scoped relay delta + AppView.** Add an `author_did` index and an author-delta endpoint (or the AppView aggregator) for efficient targeted pulls and backfill. Deferred for the privacy reason above and because Design 1 already delivers the feature on the Genesis network. Captured in Task 6 as documentation only.

**Tech stack:** Dart, Flutter, Drift, `dart test`, `dart analyze`, `flutter test`, `flutter analyze --no-fatal-infos`. (Elixir relay unchanged in the MVP.)

---

## Forward-Compatibility With The Scale Design

Per `docs/superpowers/specs/2026-06-04-scalable-following-feed-appview-design.md`,
the MVP must satisfy these so the AppView (Component D) is a drop-in later and the
MVP is not throwaway:

1. **Feed access behind a `FollowFeedSource` interface** (Task 7 below). MVP impl
   = `LocalDeltaFilterSource`; AppView impl = `AppViewTimelineSource` later.
2. **All feedable content flows through relay ops** with `author_did` + `log_id`.
   Board posts already do (this plan); murmur/note added in the companion plan.
3. **`log_id` is the universal cursor** — already true for global delta; keep all
   paging keyed on `log_id` only.
4. **Follow visibility (`localOnly` vs `federated`) recorded per follow** —
   already in the model; the UI must set it intentionally.
5. **Op payloads carry `visibility`** so a later AppView can filter public/unlisted
   without decoding local-only fields. Ensure post ops include it.

Items 2–4 are already satisfied; item 1 is added as Task 7; item 5 is handled in
the murmur/note companion plan (board posts are implicitly public within public
boards).

---

## Task 1: Sync keeps followed-users' ops

Teach `RemoteSyncService.syncFromNode` to retain ops authored by followed users, not just ops in synced boards.

**Files:**
- Modify: `ansible_node/app/lib/services/remote_sync_service.dart`
- Modify (constructor wiring): wherever `RemoteSyncService` is constructed (`ansible_node/app/lib/services/app_sync_service.dart` and DI/composition root — grep for `RemoteSyncService(`)
- Test: `ansible_node/app/test/remote_sync_following_test.dart` (new)

- [ ] **Step 1: Failing test.** New test: given a `FollowRepository` with an accepted user-follow for `did:key:alice`, and a global delta containing a `post` op authored by `did:key:alice` in a board with **no** `BoardSyncConfig`, after `syncFromNode` the post is stored locally and is returned by `FollowFeedProjector.project(followerDid: ...)`. Also assert a post by a non-followed author in a non-synced board is still dropped. Run `cd ansible_node/app && flutter test test/remote_sync_following_test.dart` → FAIL.
- [ ] **Step 2: Inject follow lookup.** Add an optional `FollowRepository? followRepository` constructor param (nullable to preserve existing call sites/tests; when null, behaviour is unchanged). At the start of `syncFromNode`, compute once:
  ```dart
  final followedAuthorDids = followRepository == null
      ? const <String>{}
      : {
          for (final edge in await followRepository!.listFollowing(
                _followerDid, targetType: FollowTargetType.user))
            if (edge.status == FollowStatus.accepted)
              (await followRepository!.getTarget(edge.targetId))?.did,
        }.whereType<String>().toSet();
  ```
  (`_followerDid` is the active local DID; thread it in the same way the projector receives `followerDid`. If not already available to the service, add it as a constructor field.)
- [ ] **Step 3: Relax the gate.** At ~L381-388 add a third allow condition:
  ```dart
  final allowedByFollowedAuthor =
      followedAuthorDids.contains(entry.activity.authorId);
  if (requireBoardSyncConfig &&
      !allowedByLegacy &&
      hostedRoute == null &&
      !allowedByFollowedAuthor) {
    continue;
  }
  ```
  Also: if `enabledBoardIdSet` and `hostedSubscriptions` are both empty (early return at ~L347-354), still proceed when `followedAuthorDids` is non-empty.
- [ ] **Step 4: Ensure storable context (stub board/thread).** Before `_applyActivity(activity)` for a followed-author op whose board/thread is missing locally, materialise minimal stubs so `_applyThreadActivity`/`_applyPostActivity` (which require `boardId!`/`threadId!`) and the projector (which iterates threads) work:
  - If `boardRepository.getById(activity.boardId)` is null → create a stub `Board(id: boardId, slug: <derived>, title: '@'+author or 'Followed', ...)` flagged as not-board-synced (reuse existing fields; no schema change).
  - If the op is a `post` and `threadRepository.getById(activity.threadId)` is null → create a stub `Thread(id: threadId, boardId: boardId, title: 'Untitled', authorId: activity.authorId, ...)`.
  - Put this in a private helper `_ensureFollowedContext(Activity activity)` invoked only on the followed-author path. Real `thread`/`board` ops arriving later overwrite the stub via existing upsert logic.
- [ ] **Step 5: Wire call sites.** Pass `followRepository` (and `followerDid`) at every `RemoteSyncService(` construction. Verify with `grep -rn "RemoteSyncService(" ansible_node`.
- [ ] **Step 6: Green + analyze.** `flutter test test/remote_sync_following_test.dart` PASS; `flutter analyze --no-fatal-infos` clean.
- [ ] **Step 7: Commit** `feat: keep followed-users' posts during relay sync`.

## Task 2: Followed-author posts survive retention pruning

Ensure posts kept only because of a user-follow are not silently pruned by board retention, and not double-counted.

**Files:**
- Modify: `ansible_node/app/lib/services/remote_sync_service.dart` (`_pruneExpiredPosts`, `_isWithinRetention`)
- Test: extend `ansible_node/app/test/remote_sync_following_test.dart`

- [ ] **Step 1: Failing test.** A followed-author post in a stub (non-config) board is retained after `_pruneExpiredPosts`, while an expired post in a retention-limited synced board is still pruned.
- [ ] **Step 2: Implement.** `_pruneExpiredPosts` only deletes within enabled board configs (already true) — confirm a stub board has no config and is therefore skipped. For `_isWithinRetention`, treat `retentionDays == null` (followed-author path) as "keep". Add a guard so a post authored by a currently-followed user is never pruned even if its stub board later gains a config.
- [ ] **Step 3: Green + analyze. Commit** `fix: retain followed-author posts through pruning`.

## Task 3: Unfollow purges locally-synced posts (exit requirement)

Constitution exit/revoke: unfollowing a user must stop syncing them and purge posts that exist only because of that follow.

**Files:**
- Modify: `ansible_core/domain/lib/src/follow/follow_service.dart` (`unfollow` for user targets)
- Possibly add: a `PostRepository` query `deleteByAuthorNotInBoards(authorDid, keepBoardIds)` or reuse existing delete APIs
- Test: `ansible_core/domain/test/follow_service_test.dart` (extend)

- [ ] **Step 1: Failing test.** After following `did:key:alice` and syncing her posts into stub boards, `unfollow` removes her edge (status `cancelled`) AND deletes her locally-synced posts that are not in any board the user still syncs (a post of hers in a board the user *also* follows is kept).
- [ ] **Step 2: Implement.** In `FollowService.unfollow` for a `FollowTargetType.user`, after setting `FollowStatus.cancelled`, compute the set of board ids the user still syncs (enabled `BoardSyncConfig` + accepted board follows) and delete posts where `authorId == targetDid AND boardId NOT IN keepSet`. Clean up now-empty stub threads/boards. Reason-code the event (`followCancelled`).
- [ ] **Step 3: Green + analyze. Commit** `feat: purge followed-user posts on unfollow`.

## Task 4: Following feed end-to-end + UI source label

Confirm the feed surfaces followed-user posts and label their provenance.

**Files:**
- Modify (if needed): `ansible_node/app/lib/screens/home_shell.dart` (Following filter already calls `FollowFeedProjector`)
- Test: `ansible_node/app/test/following_feed_test.dart` (extend)

- [ ] **Step 1: Integration test.** Follow user → sync global delta containing her post → select `FeedFilter.following` → her post appears with reason `followedUser`, even though her board is not synced.
- [ ] **Step 2: UI.** Ensure the post card renders for a stub board (board may be null/placeholder) without crashing; show a "FOLLOWING · @author" provenance label distinct from board source. Surface trust tier where already available (Base Rule 6 provenance).
- [ ] **Step 3: Green + analyze (`flutter analyze --no-fatal-infos`, `flutter test`). Commit** `feat: surface followed-user posts in Following feed`.

## Task 5 (optional): Bounded backfill for newly-followed authors

Give a newly-followed author's *existing* posts a path into the feed without waiting for new activity.

**Files:**
- Modify: `ansible_node/app/lib/services/remote_sync_service.dart` (or a small `FollowBackfillService`)

- [ ] **Step 1.** On a new accepted user-follow, run a one-time delta rescan from cursor 0 that keeps only ops authored by that DID (reuse the Task 1 gate), then discard the rescan cursor (do not move the main forward cursor backward). Cap with a max-op budget and log what was skipped if the cap is hit (no silent truncation).
- [ ] **Step 2.** Test: a follow created after old posts exist on the relay backfills those posts once. **Commit** `feat: bounded backfill for newly-followed authors`.
- [ ] **Note:** This re-reads the global stream from 0 and is acceptable on the small Genesis network only. At scale, replace with Design 2 author-scoped delta.

## Task 6 (documentation only): Design 2 / AppView path

- [ ] Record in `docs/architecture/genesis_hosting.md` (AppView TODO) the author-scoped delta design: add `author_did` index + migration on `ops`, an author-delta endpoint with per-author cursor and read rate limiting, and the **follow-graph privacy mitigation** required before it ships. No code in this plan.

## Task 7: `FollowFeedSource` abstraction (forward-compat)

Put feed retrieval behind an interface so the AppView swap is a config change.

**Files:**
- Create: `ansible_core/domain/lib/src/follow/follow_feed_source.dart`
- Modify: `ansible_core/domain/lib/ansible_domain.dart`
- Modify: `ansible_node/app/lib/screens/home_shell.dart` (consume the source)
- Test: `ansible_core/domain/test/follow_feed_source_test.dart`

- [ ] **Step 1: Failing test.** A `LocalDeltaFilterSource` implementing
  `FollowFeedSource` returns the same entries as calling `FollowFeedProjector`
  directly for a given `followerDid` + cursor.
- [ ] **Step 2: Define interface.**
  ```dart
  abstract class FollowFeedSource {
    Future<FollowFeedPage> fetch({required String followerDid, int? cursor, int limit});
  }
  ```
  `FollowFeedPage { List<FollowFeedEntry> entries; int? nextCursor; bool hasMore; }`.
  Cursor is a relay `log_id` (universal cursor, forward-compat item 3).
- [ ] **Step 3: MVP impl.** `LocalDeltaFilterSource` wraps `FollowFeedProjector`
  (and later the murmur/note `ContentItemFeedProjector`) over the locally-synced
  store. A future `AppViewTimelineSource` will call `POST /api/v1/timeline` —
  out of scope here, but the interface must not assume local-only access.
- [ ] **Step 4: Wire UI** to depend on `FollowFeedSource`, not the projector
  directly.
- [ ] **Step 5: Green + analyze. Commit** `feat: FollowFeedSource abstraction for AppView forward-compat`.

---

## Definition of Done

- Following a DID-identified user causes their public posts to appear in the Following feed (forward sync; backfill if Task 5 done).
- Non-followed authors' posts in non-synced boards are still excluded.
- Unfollowing purges that user's follow-only posts.
- No private content is fetched or sent; relay learns no follow-graph from this feature.
- `dart test` / `flutter test` green; `dart analyze` / `flutter analyze --no-fatal-infos` clean.
- Constitution Review section above remains accurate after implementation.
