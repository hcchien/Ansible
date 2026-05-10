# Forum Host Board Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace local-canonical discussion boards with Forum Host-owned hosted boards projected into the app, while keeping murmurs and notes local-owned and projectable to external targets.

**Architecture:** Forum Hosts own hosted boards, threads, posts, permissions, moderation, and distribution FE state. The app stores local projections, subscriptions, drafts, write intents, and personal content. Multi-host forum publishing uses primary hosted-board targets plus optional cross-post targets, not shared multi-primary board identity.

**Tech Stack:** Dart, Flutter, Drift, Elixir/Phoenix relay, signed ops/publication intents, existing `RemoteNode`, `Board`, `BoardSyncConfig`, `ContentItem`, `PublicationIntent`, `flutter test`, `dart test`, `mix test`.

---

## Source Documents

Read these first:

- `docs/superpowers/specs/2026-05-10-forum-host-board-design.md`
- `docs/protocol/tris_aura_federation_strategy_v0.1.md`
- `docs/superpowers/plans/2026-05-09-federation-implementation.md`
- `docs/protocol/tris_aura_sync_spec_v2.0.md`

## File Structure

Create store entities:

- `ansible_core/store/lib/src/entities/forum_host.dart`
- `ansible_core/store/lib/src/entities/hosted_board_projection.dart`
- `ansible_core/store/lib/src/entities/board_subscription.dart`
- `ansible_core/store/lib/src/entities/board_publication_target.dart`

Create Drift schemas:

- `ansible_core/store/lib/src/schema/forum_hosts.dart`
- `ansible_core/store/lib/src/schema/hosted_board_projections.dart`
- `ansible_core/store/lib/src/schema/board_subscriptions.dart`
- `ansible_core/store/lib/src/schema/board_publication_targets.dart`

Create repositories:

- `ansible_core/store/lib/src/repositories/forum_host_repository.dart`
- `ansible_core/store/lib/src/repositories/hosted_board_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_forum_host_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_hosted_board_repository.dart`
- `ansible_core/store/lib/src/repositories/in_memory/in_memory_forum_host_repository.dart`
- `ansible_core/store/lib/src/repositories/in_memory/in_memory_hosted_board_repository.dart`

Modify existing store exports and database:

- `ansible_core/store/lib/src/db/app_database.dart`
- `ansible_core/store/lib/ansible_store.dart`
- `ansible_core/store/lib/src/repositories/board_sync_config_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_board_sync_config_repository.dart`

Modify app services and UI:

- `ansible_node/app/lib/services/remote_sync_service.dart`
- `ansible_node/app/lib/services/app_sync_service.dart`
- `ansible_node/app/lib/services/content_publication_service.dart`
- `ansible_node/app/lib/screens/sync_settings_screen.dart`
- `ansible_node/app/lib/screens/home_shell.dart`
- `ansible_node/app/lib/widgets/thread_form_dialog.dart`
- `ansible_node/app/lib/widgets/board_form_dialog.dart`

Modify relay:

- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/ops_controller.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Add hosted board discovery/create endpoints under `/api/v1/forum-host/*`.

## Task 1: Store Model For Forum Hosts And Hosted Board Projections

**Files:**

- Create the four entity files listed above.
- Create the four schema files listed above.
- Modify `ansible_core/store/lib/src/db/app_database.dart`.
- Modify `ansible_core/store/lib/ansible_store.dart`.
- Test `ansible_core/store/test/forum_host_repository_test.dart`.
- Test `ansible_core/store/test/hosted_board_repository_test.dart`.

- [ ] **Step 1: Write failing repository tests**

Create tests proving:

```dart
test('hosted board projection preserves host-owned identity', () async {
  final repo = InMemoryHostedBoardRepository();
  final now = DateTime.utc(2026, 5, 10);

  await repo.upsertProjection(HostedBoardProjection(
    localBoardId: 'local-general',
    forumHostId: 'host-1',
    hostedBoardId: 'remote-general',
    canonicalBoardUri: 'https://forum.example/boards/remote-general',
    remoteSlug: 'general',
    localSlug: 'general',
    title: 'General',
    permissions: const {'read': true, 'write': true},
    lastSeenCursor: 0,
    createdAt: now,
    updatedAt: now,
  ));

  final projection = await repo.getProjection('host-1', 'remote-general');
  expect(projection!.canonicalBoardUri, 'https://forum.example/boards/remote-general');
});
```

Add a second test proving same `remoteSlug` on two hosts keeps distinct
projections with distinct `forumHostId`.

Run:

```bash
cd ansible_core/store
dart test test/forum_host_repository_test.dart test/hosted_board_repository_test.dart
```

Expected: fail because entities/repositories do not exist.

- [ ] **Step 2: Implement entities**

Add `ForumHost`, `HostedBoardProjection`, `BoardSubscription`, and
`BoardPublicationTarget` with the fields from the design spec. Keep enums small:

```dart
enum BoardPublicationMode { primary, crossPost, projection }
enum BoardPublicationStatus { pending, accepted, failed, rejected }
```

- [ ] **Step 3: Implement schemas and repositories**

Add Drift tables with primary keys:

- `forumHosts`: `forumHostId`
- `hostedBoardProjections`: `localBoardId`
- `boardSubscriptions`: `subscriptionId`
- `boardPublicationTargets`: `targetId`

Add unique constraints:

- hosted board identity: `(forumHostId, hostedBoardId)`
- local routing slug: `localSlug`
- subscription identity: `(forumHostId, hostedBoardId)`

- [ ] **Step 4: Generate Drift code**

Run:

```bash
cd ansible_core/store
dart run build_runner build --delete-conflicting-outputs
```

Expected: `lib/src/db/app_database.g.dart` updates cleanly.

- [ ] **Step 5: Verify store tests**

Run:

```bash
cd ansible_core/store
dart test test/forum_host_repository_test.dart test/hosted_board_repository_test.dart
```

Expected: all tests pass.

## Task 2: Compatibility Bridge From RemoteNode And BoardSyncConfig

**Files:**

- Modify `ansible_core/store/lib/src/entities/remote_node.dart`.
- Modify `ansible_core/store/lib/src/entities/board_sync_config.dart`.
- Modify `ansible_core/store/lib/src/repositories/drift/drift_remote_node_repository.dart`.
- Modify `ansible_core/store/lib/src/repositories/drift/drift_board_sync_config_repository.dart`.
- Test `ansible_core/store/test/forum_host_compatibility_test.dart`.

- [ ] **Step 1: Write failing compatibility tests**

Add tests proving an active `RemoteNode` can be exposed as a `ForumHost` during
migration, and an existing enabled `BoardSyncConfig` can be converted into a
`BoardSubscription` only when a hosted board projection exists.

Run:

```bash
cd ansible_core/store
dart test test/forum_host_compatibility_test.dart
```

Expected: fail because compatibility helpers do not exist.

- [ ] **Step 2: Add migration helpers**

Create methods:

```dart
extension RemoteNodeForumHostCompat on RemoteNode {
  ForumHost toForumHost() => ForumHost(
    forumHostId: id,
    displayName: name,
    baseUrl: url,
    canonicalHostUri: url,
    serverKind: 'ansibleForumHost',
    capabilities: const {},
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

Add repository-level read methods so UI can list Forum Hosts even before the
full migration removes `RemoteNode`.

- [ ] **Step 3: Verify compatibility**

Run:

```bash
cd ansible_core/store
dart test test/forum_host_compatibility_test.dart test/drift_remote_node_repository_test.dart test/drift_board_sync_config_repository_test.dart
```

Expected: all tests pass.

## Task 3: Forum Host Discovery And Hosted Board APIs

**Files:**

- Create `ansible_node/app/lib/services/forum_host_client.dart`.
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`.
- Create `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`.
- Test `ansible_node/app/test/forum_host_client_test.dart`.
- Test `ansible_relay/phoenix/test/forum_host_controller_test.exs`.

- [ ] **Step 1: Write failing API contract tests**

App client tests should expect:

```dart
final host = await client.getHostInfo();
expect(host['server_kind'], 'ansibleForumHost');
final boards = await client.listHostedBoards();
expect(boards.single['canonical_board_uri'], 'https://forum.example/boards/general');
```

Relay tests should expect:

- `GET /api/v1/forum-host` returns host metadata.
- `GET /api/v1/forum-host/boards` returns hosted boards.
- `POST /api/v1/forum-host/boards` accepts a signed create-board intent.

- [ ] **Step 2: Implement client and relay endpoints**

Implement minimal JSON endpoints:

```json
{
  "forum_host_id": "host-local-dev",
  "display_name": "Local Forum Host",
  "server_kind": "ansibleForumHost",
  "capabilities": {
    "create_boards": true,
    "create_threads": true,
    "cross_post": true
  }
}
```

- [ ] **Step 3: Verify API tests**

Run:

```bash
cd ansible_node/app
flutter test test/forum_host_client_test.dart
cd ../../ansible_relay/phoenix
mix test test/forum_host_controller_test.exs
```

Expected: all tests pass.

## Task 4: Pull Sync Uses Board Subscriptions

**Files:**

- Modify `ansible_node/app/lib/services/remote_sync_service.dart`.
- Modify `ansible_node/app/lib/services/app_sync_service.dart`.
- Test `ansible_node/app/test/remote_sync_service_test.dart`.
- Test `ansible_node/app/test/app_sync_service_test.dart`.

- [ ] **Step 1: Write failing pull tests**

Add tests proving foreground pull:

- reads active Forum Hosts
- filters by `BoardSubscription`
- updates per-subscription cursor
- upserts hosted board/thread/post projections
- does not require legacy `BoardSyncConfig`

- [ ] **Step 2: Implement subscription-driven pull**

Replace board filtering based only on `BoardSyncConfig` with hosted board
subscription filtering. Keep the legacy path behind a compatibility adapter
until migration is complete.

- [ ] **Step 3: Verify pull tests**

Run:

```bash
cd ansible_node/app
flutter test test/remote_sync_service_test.dart test/app_sync_service_test.dart
```

Expected: all tests pass.

## Task 5: Forum Write Intents And Board Publication Targets

**Files:**

- Modify `ansible_node/app/lib/services/content_publication_service.dart`.
- Modify `ansible_node/app/lib/services/ops_dispatch_service.dart`.
- Create `ansible_node/app/lib/services/forum_publication_service.dart`.
- Test `ansible_node/app/test/forum_publication_service_test.dart`.
- Test `ansible_node/app/test/content_publication_service_test.dart`.

- [ ] **Step 1: Write failing write-target tests**

Add tests proving:

- create thread requires one primary hosted board target
- cross-post targets create independent `BoardPublicationTarget` rows
- note/murmur projection to a hosted board keeps the original `ContentItem`
  canonical locally
- private note/murmur cannot be projected

- [ ] **Step 2: Implement forum publication service**

Implement `ForumPublicationService` with methods:

```dart
Future<ForumPublicationResult> createThread({
  required String localDraftId,
  required String primaryTargetId,
  List<String> crossPostTargetIds = const [],
});

Future<ForumPublicationResult> projectContentItem({
  required String contentItemId,
  required List<String> targetIds,
});
```

Each target records independent status and remote ids.

- [ ] **Step 3: Verify publication tests**

Run:

```bash
cd ansible_node/app
flutter test test/forum_publication_service_test.dart test/content_publication_service_test.dart
```

Expected: all tests pass.

## Task 6: UI Rename And Create Hosted Board Flow

**Files:**

- Modify `ansible_node/app/lib/screens/sync_settings_screen.dart`.
- Modify `ansible_node/app/lib/screens/home_shell.dart`.
- Modify `ansible_node/app/lib/widgets/board_form_dialog.dart`.
- Modify `ansible_node/app/lib/widgets/thread_form_dialog.dart`.
- Test `ansible_node/app/test/forum_host_settings_screen_test.dart`.
- Test `ansible_node/app/test/home_shell_sync_test.dart`.
- Test `ansible_node/app/test/widget_test.dart`.

- [ ] **Step 1: Write failing UI tests**

Test expected user flows:

- Sync settings labels say "Forum Host".
- Hosted board subscriptions are listed under each Forum Host.
- Create board requires selecting a Forum Host.
- If no Forum Host exists, create discussion board is disabled and explains
  that boards live on Forum Hosts.
- Thread creation requires selecting a hosted board target.

- [ ] **Step 2: Implement UI rename**

Rename product copy:

- "relay server" or generic "server" in discussion-board UI -> "Forum Host"
- "Boards to Sync" -> "Hosted boards"
- "Create board" in discussion UI -> "Create hosted board"

Protocol-specific Nostr relay copy remains "Nostr relay".

- [ ] **Step 3: Implement create hosted board flow**

Change board creation:

1. User selects Forum Host.
2. User enters title/description.
3. App sends create-hosted-board intent.
4. App stores returned hosted board projection.
5. App subscribes to the created board.

- [ ] **Step 4: Verify UI tests**

Run:

```bash
cd ansible_node/app
flutter test test/forum_host_settings_screen_test.dart test/home_shell_sync_test.dart test/widget_test.dart
```

Expected: all tests pass.

## Task 7: Local Collections Split

**Files:**

- Create `ansible_core/store/lib/src/entities/local_collection.dart`.
- Create `ansible_core/store/lib/src/schema/local_collections.dart`.
- Create `ansible_core/store/lib/src/repositories/local_collection_repository.dart`.
- Create `ansible_core/store/lib/src/repositories/drift/drift_local_collection_repository.dart`.
- Modify note/workspace UI only if it currently needs local grouping.
- Test `ansible_core/store/test/local_collection_repository_test.dart`.

- [ ] **Step 1: Write failing local collection tests**

Add tests proving local collections can group local `ContentItem`s without
creating forum boards or forum sync targets.

- [ ] **Step 2: Implement local collections**

Implement fields:

- `collectionId`
- `ownerDid`
- `title`
- `description`
- `createdAt`
- `updatedAt`
- `isDeleted`

- [ ] **Step 3: Verify local collection tests**

Run:

```bash
cd ansible_core/store
dart test test/local_collection_repository_test.dart
```

Expected: all tests pass.

## Task 8: Migration Cleanup And Documentation Updates

**Files:**

- Modify `docs/protocol/tris_aura_federation_strategy_v0.1.md`.
- Modify `docs/protocol/tris_aura_sync_spec_v2.0.md`.
- Modify `docs/superpowers/specs/2026-05-09-federation-strategy-design.md`.
- Modify or add app tests that reference local-only boards.

- [ ] **Step 1: Add transition notes**

Update docs to state:

- Forum Hosts own discussion boards.
- Local board rows are projections during migration.
- `murmur` and `note` remain local canonical content.
- Multi-host discussion uses cross-post targets, not shared board identity.

- [ ] **Step 2: Add migration assertions**

Add tests proving existing local boards are treated as legacy projections until
they are bound to a Forum Host or converted into Local Collections.

- [ ] **Step 3: Run full relevant suites**

Run:

```bash
cd ansible_core/store
dart test
cd ../../ansible_node/app
flutter test
cd ../../ansible_relay/phoenix
mix test
```

Expected: all tests pass or only pre-existing analyzer info remains documented
in the final handoff.

## Plan Self-Review

Spec coverage:

- Forum Host ownership: Tasks 1, 3, 6, 8.
- Local projections and subscriptions: Tasks 1, 2, 4.
- Personal content projection: Task 5.
- Required Forum Host for discussion board creation: Task 6.
- Cross-post instead of multi-primary board sync: Tasks 1 and 5.
- Local Collections split: Task 7.
- Migration from `RemoteNode` and `BoardSyncConfig`: Tasks 2 and 8.

No implementation task should create local-only discussion boards. Any local-only
organizing surface belongs to Task 7 Local Collections.
