# Content Lineage Transformation And AI Assistance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Ansible's local-first content lineage model, manual transformations, AI provider integration, context packs, review flows, summaries, and public Lexicon sync.

**Architecture:** `ansible_core/store` owns canonical local data: content items, mode metadata, relations, transformations, context packs, summaries, and provider configs. `ansible_node/app` owns provider secrets in Keychain, low-friction AI setup, context pack building, provider calls, and review UI. `ansible_core/vc` and `ansible_relay/phoenix` add public Lexicon records only after local behavior is stable.

**Tech Stack:** Dart, Flutter, Drift, `flutter_secure_storage`, `http`, existing repository patterns, existing XRPC relay, `dart test`, `dart run build_runner`, `flutter test`, `mix test`.

---

## Source Specs

Read these first:

- `docs/superpowers/specs/2026-05-06-content-lineage-transformation-design.md`
- `docs/protocol/tris_aura_content_lineage_lexicon_v0.1.md`

Implementation boundaries:

- Private murmurs and notes are local-only by default.
- API keys live in Keychain, never Drift.
- AI reads immutable `ContextPack` snapshots, not live database rows.
- AI output never publishes automatically.
- Manual transformation must work before AI provider integration.
- Existing board/thread/post forum behavior must keep working during migration.

## File Structure

Create store entities:

- `ansible_core/store/lib/src/entities/content_item.dart`
- `ansible_core/store/lib/src/entities/content_relation.dart`
- `ansible_core/store/lib/src/entities/transformation_job.dart`
- `ansible_core/store/lib/src/entities/projection.dart`
- `ansible_core/store/lib/src/entities/discussion_node.dart`
- `ansible_core/store/lib/src/entities/ownership_policy.dart`
- `ansible_core/store/lib/src/entities/ai_provider_config.dart`
- `ansible_core/store/lib/src/entities/context_pack.dart`
- `ansible_core/store/lib/src/entities/summary_job.dart`

Create Drift schema:

- `ansible_core/store/lib/src/schema/content_items.dart`
- `ansible_core/store/lib/src/schema/content_metadata.dart`
- `ansible_core/store/lib/src/schema/content_relations.dart`
- `ansible_core/store/lib/src/schema/transformation_jobs.dart`
- `ansible_core/store/lib/src/schema/projections.dart`
- `ansible_core/store/lib/src/schema/discussion_nodes.dart`
- `ansible_core/store/lib/src/schema/ownership_policies.dart`
- `ansible_core/store/lib/src/schema/ai_provider_configs.dart`
- `ansible_core/store/lib/src/schema/context_packs.dart`
- `ansible_core/store/lib/src/schema/summary_jobs.dart`

Modify database and exports:

- `ansible_core/store/lib/src/db/app_database.dart`
- `ansible_core/store/lib/src/db/app_database.g.dart`
- `ansible_core/store/lib/ansible_store.dart`

Create repositories:

- `ansible_core/store/lib/src/repositories/content_item_repository.dart`
- `ansible_core/store/lib/src/repositories/content_relation_repository.dart`
- `ansible_core/store/lib/src/repositories/transformation_job_repository.dart`
- `ansible_core/store/lib/src/repositories/projection_repository.dart`
- `ansible_core/store/lib/src/repositories/discussion_node_repository.dart`
- `ansible_core/store/lib/src/repositories/ai_assistance_repository.dart`
- Drift and in-memory implementations under existing repository folders.

Create app AI services:

- `ansible_node/app/lib/services/ai/ai_provider.dart`
- `ansible_node/app/lib/services/ai/ai_provider_config_store.dart`
- `ansible_node/app/lib/services/ai/context_pack_builder.dart`
- `ansible_node/app/lib/services/ai/openai_compatible_provider.dart`
- `ansible_node/app/lib/services/ai/local_http_provider.dart`
- `ansible_node/app/lib/services/ai/manual_ai_provider.dart`
- `ansible_node/app/lib/services/ai/ai_privacy_policy.dart`

Create Flutter screens/widgets:

- `ansible_node/app/lib/screens/murmur_screen.dart`
- `ansible_node/app/lib/screens/note_workspace_screen.dart`
- `ansible_node/app/lib/screens/discussion_detail_screen.dart`
- `ansible_node/app/lib/widgets/ai_provider_setup_sheet.dart`
- `ansible_node/app/lib/widgets/transformation_review_sheet.dart`
- `ansible_node/app/lib/widgets/summary_review_sheet.dart`
- `ansible_node/app/lib/widgets/lineage_inspector_sheet.dart`

Modify existing Flutter entry points:

- `ansible_node/app/lib/screens/home_shell.dart`
- `ansible_node/app/lib/main.dart`

Create Lexicon and relay changes:

- Modify `ansible_core/vc/lib/src/lexicon_record.dart`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/controllers/xrpc_controller.ex`
- Add relay tests in `ansible_relay/phoenix/test/xrpc_controller_test.exs`

---

## Task 1: Store Schema And Entity Foundation

**Files:**

- Create store entity and schema files listed above.
- Modify: `ansible_core/store/lib/src/db/app_database.dart`
- Modify: `ansible_core/store/lib/ansible_store.dart`
- Generate: `ansible_core/store/lib/src/db/app_database.g.dart`
- Test: `ansible_core/store/test/content_lineage_schema_test.dart`

- [x] **Step 1: Write failing schema smoke test**

Create `ansible_core/store/test/content_lineage_schema_test.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('content lineage schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('database exposes content lineage and AI assistance tables', () {
      final tableNames = db.allTables.map((table) => table.actualTableName);

      expect(tableNames, contains('content_items'));
      expect(tableNames, contains('murmur_metadata'));
      expect(tableNames, contains('note_metadata'));
      expect(tableNames, contains('post_metadata'));
      expect(tableNames, contains('discussion_metadata'));
      expect(tableNames, contains('content_relations'));
      expect(tableNames, contains('transformation_jobs'));
      expect(tableNames, contains('context_packs'));
      expect(tableNames, contains('summary_jobs'));
      expect(tableNames, contains('ai_provider_configs'));
    });
  });
}
```

Run:

```bash
cd ansible_core/store
dart test test/content_lineage_schema_test.dart
```

Expected: FAIL because the tables do not exist.

- [x] **Step 2: Add entities and enums**

Create entities with parse helpers matching existing `FollowTargetType` style:

- `ContentMode`: `murmur`, `note`, `post`, `discussion`
- `ContentStatus`: `draft`, `active`, `archived`, `removed`, `rejected`
- `ContentVisibility`: `private`, `unlisted`, `public`
- `RelationType`: `expandedFrom`, `projectedFrom`, `summarizedFrom`, `forkedFrom`, `supports`, `rebuts`, `references`
- `AiProviderType`: `manual`, `openaiCompatible`, `localHttp`, `system`
- `ContextPackPurpose`: `murmurToNote`, `noteToDiscussion`, `discussionSummary`, `followingSummary`, `boardSummary`
- `ContextPrivacyLevel`: `publicOnly`, `containsPrivate`, `containsSensitive`

Run:

```bash
cd ansible_core/store
dart format lib/src/entities
dart analyze lib/src/entities
```

Expected: analysis exits 0.

- [x] **Step 3: Add Drift tables and migration**

Add all schema tables to `AppDatabase`, bump `schemaVersion`, and add guarded
`_createTableIfMissing` calls in `onUpgrade`.

Run:

```bash
cd ansible_core/store
dart run build_runner build --delete-conflicting-outputs
dart test test/content_lineage_schema_test.dart
```

Expected: PASS.

- [x] **Step 4: Export public store APIs**

Export the new entities and repositories from `ansible_store.dart`. Hide new
Drift row classes in the final database export if their names collide with
entity classes.

Run:

```bash
cd ansible_core/store
dart analyze lib/ansible_store.dart lib/src/db/app_database.dart
```

Expected: analysis exits 0.

## Task 2: Repositories And Local Lineage Queries

**Files:**

- Create repository interfaces and Drift/in-memory implementations.
- Test: `ansible_core/store/test/content_lineage_repository_test.dart`

- [x] **Step 1: Write failing repository tests**

Create tests covering:

- create/list content item by mode
- create relation from note to murmur
- query sources for derived content
- query derived content for source content
- default private content is `localOnly = true`

Run:

```bash
cd ansible_core/store
dart test test/content_lineage_repository_test.dart
```

Expected: FAIL because repositories are missing.

- [x] **Step 2: Implement content item and relation repositories**

Methods required:

```dart
abstract class ContentItemRepository {
  Future<ContentItem?> getById(String id);
  Future<List<ContentItem>> list({ContentMode? mode, String? authorDid});
  Future<void> create(ContentItem item);
  Future<void> update(ContentItem item);
  Future<void> delete(String id);
}

abstract class ContentRelationRepository {
  Future<void> create(ContentRelation relation);
  Future<List<ContentRelation>> sourcesFor(String contentItemId);
  Future<List<ContentRelation>> derivedFrom(String contentItemId);
}
```

Run:

```bash
cd ansible_core/store
dart test test/content_lineage_repository_test.dart
```

Expected: PASS.

- [x] **Step 3: Implement transformation, projection, context, summary, and provider repositories**

Use focused methods that match the first UI flows:

- create job
- add sources
- mark completed
- mark accepted
- create context pack
- create summary job
- save provider metadata without secret values

Run:

```bash
cd ansible_core/store
dart test test/content_lineage_repository_test.dart
dart analyze lib test
```

Expected: tests pass; analysis has no errors.

## Task 3: Manual Transformation Domain Flow

**Files:**

- Create: `ansible_core/domain/lib/src/content/content_transformation_service.dart`
- Create: `ansible_core/domain/lib/src/content/content_lineage_projector.dart`
- Modify: `ansible_core/domain/lib/ansible_domain.dart`
- Test: `ansible_core/domain/test/content_transformation_service_test.dart`

- [x] **Step 1: Write failing Murmur -> Note test**

Test that selected murmur IDs create:

- one `TransformationJob`
- one note `ContentItem`
- one `expanded_from` relation per source murmur

Run:

```bash
cd ansible_core/domain
dart test test/content_transformation_service_test.dart
```

Expected: FAIL because the service does not exist.

- [x] **Step 2: Implement manual Murmur -> Note**

Service method:

```dart
Future<ContentItem> acceptManualMurmurToNote({
  required String authorDid,
  required List<ContentItem> sourceMurmurs,
  required String noteBody,
  String? noteTitle,
});
```

Run:

```bash
cd ansible_core/domain
dart test test/content_transformation_service_test.dart
```

Expected: PASS for Murmur -> Note.

- [x] **Step 3: Add Note -> Discussion projection test**

Test that accepting projection creates:

- discussion `ContentItem`
- `projection`
- `projected_from` relation
- compatibility `Thread`

Run:

```bash
cd ansible_core/domain
dart test test/content_transformation_service_test.dart
```

Expected: FAIL until projection implementation exists.

- [x] **Step 4: Implement Note -> Discussion projection**

Service method:

```dart
Future<ContentItem> acceptNoteToDiscussion({
  required String authorDid,
  required ContentItem sourceNote,
  required String title,
  required String body,
  required bool ownershipTransferAcknowledged,
});
```

Reject with `ArgumentError` when acknowledgement is false.

Run:

```bash
cd ansible_core/domain
dart test test/content_transformation_service_test.dart
dart analyze lib test
```

Expected: tests pass; analysis exits 0.

## Task 4: AI Provider Boundary And Privacy Policy

**Files:**

- Create files under `ansible_node/app/lib/services/ai/`.
- Test: `ansible_node/app/test/ai_provider_test.dart`
- Test: `ansible_node/app/test/ai_privacy_policy_test.dart`

- [x] **Step 1: Write provider and privacy tests**

Test cases:

- manual provider returns deterministic draft output without network
- OpenAI-compatible provider sends `messages` and parses JSON response
- private context pack is blocked for remote provider without consent
- API key value is retrieved through `AiProviderConfigStore`, not from Drift

Run:

```bash
cd ansible_node/app
flutter test test/ai_provider_test.dart test/ai_privacy_policy_test.dart
```

Expected: FAIL because services do not exist.

- [x] **Step 2: Implement provider interface**

Core interface:

```dart
abstract class AiProvider {
  Future<AiProviderResult> complete(AiProviderRequest request);
}

class AiProviderRequest {
  final String task;
  final Map<String, dynamic> contextPack;
  final Map<String, dynamic> outputSchema;

  const AiProviderRequest({
    required this.task,
    required this.contextPack,
    required this.outputSchema,
  });
}
```

Run:

```bash
cd ansible_node/app
dart format lib/services/ai test/ai_provider_test.dart test/ai_privacy_policy_test.dart
flutter test test/ai_provider_test.dart test/ai_privacy_policy_test.dart
```

Expected: manual and privacy tests pass.

- [x] **Step 3: Implement OpenAI-compatible provider**

Use `http.Client` injection for tests. Request shape:

```json
{
  "model": "model_name",
  "messages": [
    {"role": "system", "content": "Return JSON only."},
    {"role": "user", "content": "...serialized context pack..."}
  ],
  "temperature": 0.2
}
```

Run:

```bash
cd ansible_node/app
flutter test test/ai_provider_test.dart
```

Expected: provider parses mocked response and returns structured JSON.

## Task 5: Low-Friction Flutter AI Setup And Review UI

**Files:**

- Create AI setup/review widgets listed in File Structure.
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Test: `ansible_node/app/test/ai_setup_flow_test.dart`
- Test: `ansible_node/app/test/transformation_review_flow_test.dart`

- [x] **Step 1: Write failing widget tests**

Test cases:

- first AI action opens provider setup sheet
- successful test connection returns to original action
- transformation review does not create content until user taps accept
- summary review can save result as private note

Run:

```bash
cd ansible_node/app
flutter test test/ai_setup_flow_test.dart test/transformation_review_flow_test.dart
```

Expected: FAIL because UI is missing.

- [x] **Step 2: Build provider setup sheet**

The sheet must contain:

- provider type selector
- base URL input
- model input
- API key input
- test connection button
- save and continue action

Run:

```bash
cd ansible_node/app
flutter test test/ai_setup_flow_test.dart
```

Expected: setup flow test passes.

- [x] **Step 3: Build transformation and summary review sheets**

Review sheets must show source boundaries, generated output, discard, edit, and
accept/save actions.

Run:

```bash
cd ansible_node/app
flutter test test/transformation_review_flow_test.dart
flutter analyze --no-fatal-infos
```

Expected: tests pass; analyze has no errors.

## Task 6: Murmur, Note, Discussion, And Summary Screens

**Files:**

- Create new screens listed in File Structure.
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Test: `ansible_node/app/test/content_modes_navigation_test.dart`
- Test: `ansible_node/app/test/summary_review_flow_test.dart`

- [x] **Step 1: Write failing navigation and mobile layout tests**

Verify:

- phone width uses compact navigation, not fixed sidebar
- mode navigation exposes Murmur, Notes, Discussions
- Murmur create enforces 500-character limit
- Discussion summary action opens summary review

Run:

```bash
cd ansible_node/app
flutter test test/content_modes_navigation_test.dart test/summary_review_flow_test.dart
```

Expected: FAIL until screens exist.

- [x] **Step 2: Implement screens incrementally**

Build screens using existing dark visual language from `home_shell.dart`.
Keep dense, app-like controls; avoid landing-page composition.

Run:

```bash
cd ansible_node/app
flutter test test/content_modes_navigation_test.dart test/summary_review_flow_test.dart
```

Expected: PASS.

## Task 7: Lexicon Records And Relay Validation

**Files:**

- Modify: `ansible_core/vc/lib/src/lexicon_record.dart`
- Test: `ansible_core/vc/test/lexicon_record_test.dart`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/xrpc_controller.ex`
- Test: `ansible_relay/phoenix/test/xrpc_controller_test.exs`

- [x] **Step 1: Write failing Lexicon tests**

Test JSON for:

- `LexiconMurmur`
- `LexiconNote`
- `LexiconDiscussion`
- `LexiconContentRelation`
- `LexiconTransformation`
- `LexiconProjection`

Run:

```bash
cd ansible_core/vc
dart test test/lexicon_record_test.dart
```

Expected: FAIL because classes are missing.

- [x] **Step 2: Implement Lexicon record classes**

Add classes matching `docs/protocol/tris_aura_content_lineage_lexicon_v0.1.md`.

Run:

```bash
cd ansible_core/vc
dart test test/lexicon_record_test.dart
dart analyze lib test
```

Expected: PASS and analysis exits 0.

- [x] **Step 3: Add relay validation tests**

Test:

- valid new records return 200
- mismatched `collection` and `$type` returns 422
- missing required field returns 422
- existing `io.trisaura.post` still returns 200

Run:

```bash
cd ansible_relay/phoenix
mix test test/xrpc_controller_test.exs
```

Expected: FAIL until validation is implemented.

- [x] **Step 4: Implement relay validation**

Keep validation lightweight in `XrpcController`:

- check `collection == record["$type"]`
- validate required fields by collection
- reject private-only public fields

Run:

```bash
cd ansible_relay/phoenix
mix test test/xrpc_controller_test.exs
mix test
```

Expected: all relay tests pass.

## Task 8: End-To-End Integration Tests

**Files:**

- Create: `ansible_node/app/test/content_lineage_integration_test.dart`
- Create: `ansible_node/app/test/ai_summary_integration_test.dart`

- [x] **Step 1: Write integration tests**

Cover:

- create murmur
- transform murmur to note with manual provider
- project note to discussion
- inspect lineage
- summarize discussion with manual provider
- save summary as private note

Run:

```bash
cd ansible_node/app
flutter test test/content_lineage_integration_test.dart test/ai_summary_integration_test.dart
```

Expected: FAIL until previous tasks are integrated.

- [x] **Step 2: Wire services into app composition**

Update app construction to pass repositories, AI provider store, and provider
factory into the new screens without global mutable state.

Run:

```bash
cd ansible_node/app
flutter test test/content_lineage_integration_test.dart test/ai_summary_integration_test.dart
flutter test
flutter analyze --no-fatal-infos
```

Expected: all app tests pass; analyze has no errors.

## Completion Checks

Run all relevant suites:

```bash
cd ansible_core/store
dart test
dart analyze lib test
```

```bash
cd ansible_core/domain
dart test
dart analyze lib test
```

```bash
cd ansible_core/vc
dart test
dart analyze lib test
```

```bash
cd ansible_node/app
flutter test
flutter analyze --no-fatal-infos
```

```bash
cd ansible_relay/phoenix
mix test
```

Expected: all commands pass. Existing info-level Flutter lints can remain only
if they are already present and not introduced by this work.

## Commit Slices

Use small commits:

1. `feat(store): add content lineage schema`
2. `feat(store): add content lineage repositories`
3. `feat(domain): add manual content transformations`
4. `feat(app): add ai provider boundary`
5. `feat(app): add content mode screens`
6. `feat(vc): add content lineage lexicon records`
7. `feat(relay): validate content lineage records`
8. `test: add content lineage integration coverage`
