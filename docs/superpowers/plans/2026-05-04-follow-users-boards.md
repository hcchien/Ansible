# Follow Users And Boards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build local-first follow users and follow boards, including local store state, ActivityPub-compatible protocol models, domain transitions, board sync integration, Following feed projection, and Flutter UI entry points.

**Architecture:** Follow state lives in `ansible_core/store` as follow targets, follow edges, event logs, and an outbound delivery queue. `ansible_core/domain` owns state transitions and feed projection, `ansible_core/ap` owns ActivityPub-compatible serialization, `ansible_sync/handlers` routes inbound follow activities, and `ansible_node/app` exposes follow controls and a Following feed filter.

**Tech Stack:** Dart, Flutter, Drift, ActivityPub-compatible JSON, existing repository patterns, `dart test`, `dart analyze`, `flutter test`, `flutter analyze --no-fatal-infos`.

---

## Source Spec

Read this first:

- `docs/superpowers/specs/2026-05-04-follow-users-boards-design.md`

Important boundaries:

- Follow is social subscription state, not identity proofing.
- Follow envelopes must not contain Wallet credential payloads or Taiwan digital identity assertions.
- Remote board follows toggle `BoardSyncConfig.syncEnabled`.
- `FollowEdge` is authoritative for relationship state; outbound delivery queue is transport state only.

## File Structure

Create store entities:

- `ansible_core/store/lib/src/entities/follow_target.dart`
- `ansible_core/store/lib/src/entities/follow_edge.dart`
- `ansible_core/store/lib/src/entities/follow_activity_event.dart`
- `ansible_core/store/lib/src/entities/outbound_follow_activity.dart`

Create store schema:

- `ansible_core/store/lib/src/schema/follow_targets.dart`
- `ansible_core/store/lib/src/schema/follow_edges.dart`
- `ansible_core/store/lib/src/schema/follow_activity_events.dart`
- `ansible_core/store/lib/src/schema/outbound_follow_activities.dart`

Modify database and exports:

- `ansible_core/store/lib/src/db/app_database.dart`
- `ansible_core/store/lib/src/db/app_database.g.dart`
- `ansible_core/store/lib/ansible_store.dart`

Create repository interfaces and implementations:

- `ansible_core/store/lib/src/repositories/follow_repository.dart`
- `ansible_core/store/lib/src/repositories/follow_activity_outbox_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_follow_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_follow_activity_outbox_repository.dart`
- `ansible_core/store/lib/src/repositories/in_memory/in_memory_follow_repository.dart`
- `ansible_core/store/lib/src/repositories/in_memory/in_memory_follow_activity_outbox_repository.dart`

Create AP protocol models:

- `ansible_core/ap/lib/src/follow_activities.dart`
- Modify `ansible_core/ap/lib/ansible_ap.dart`

Create domain services:

- `ansible_core/domain/lib/src/follow/follow_service.dart`
- `ansible_core/domain/lib/src/follow/follow_feed_projector.dart`
- `ansible_core/domain/lib/src/follow/follow_result.dart`
- Modify `ansible_core/domain/lib/ansible_domain.dart`

Modify sync handlers:

- `ansible_sync/handlers/lib/src/controllers/follow_inbox_controller.dart`
- Modify `ansible_sync/handlers/lib/ansible_sync.dart`

Modify Flutter app:

- `ansible_node/app/lib/screens/home_shell.dart`
- `ansible_node/app/lib/screens/boards_list_screen.dart`
- Create `ansible_node/app/lib/widgets/follow_button.dart`
- Create `ansible_node/app/lib/widgets/feed_filter_tabs.dart`

Create tests:

- `ansible_core/store/test/drift_follow_repository_test.dart`
- `ansible_core/store/test/follow_repository_in_memory_test.dart`
- `ansible_core/ap/test/follow_activities_test.dart`
- `ansible_core/domain/test/follow_service_test.dart`
- `ansible_core/domain/test/follow_feed_projector_test.dart`
- `ansible_sync/handlers/test/follow_inbox_controller_test.dart`
- `ansible_node/app/test/follow_button_test.dart`
- `ansible_node/app/test/following_feed_test.dart`

---

## Task 1: Store Entities And Drift Schema

**Files:**

- Create: `ansible_core/store/lib/src/entities/follow_target.dart`
- Create: `ansible_core/store/lib/src/entities/follow_edge.dart`
- Create: `ansible_core/store/lib/src/entities/follow_activity_event.dart`
- Create: `ansible_core/store/lib/src/entities/outbound_follow_activity.dart`
- Create: `ansible_core/store/lib/src/schema/follow_targets.dart`
- Create: `ansible_core/store/lib/src/schema/follow_edges.dart`
- Create: `ansible_core/store/lib/src/schema/follow_activity_events.dart`
- Create: `ansible_core/store/lib/src/schema/outbound_follow_activities.dart`
- Modify: `ansible_core/store/lib/src/db/app_database.dart`
- Modify: `ansible_core/store/lib/ansible_store.dart`
- Generate: `ansible_core/store/lib/src/db/app_database.g.dart`
- Test: `ansible_core/store/test/drift_follow_repository_test.dart`

- [ ] **Step 1: Write failing schema smoke tests**

Create `ansible_core/store/test/drift_follow_repository_test.dart` with this initial content:

```dart
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('follow schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('database exposes follow tables', () async {
      final tableNames = db.allTables.map((table) => table.actualTableName);

      expect(tableNames, contains('follow_targets'));
      expect(tableNames, contains('follow_edges'));
      expect(tableNames, contains('follow_activity_events'));
      expect(tableNames, contains('outbound_follow_activities'));
    });
  });
}
```

Run:

```bash
cd ansible_core/store
dart test test/drift_follow_repository_test.dart
```

Expected: FAIL because follow tables do not exist.

- [ ] **Step 2: Add entity enums and models**

Create `follow_target.dart`:

```dart
enum FollowTargetType {
  user,
  board;

  static FollowTargetType parse(String value) {
    return FollowTargetType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown FollowTargetType "$value"'),
    );
  }
}

class FollowTarget {
  final String targetId;
  final FollowTargetType targetType;
  final String? canonicalUri;
  final String displayName;
  final String? handle;
  final String? did;
  final String? actorUri;
  final String? inboxUri;
  final String? outboxUri;
  final String? remoteNodeId;
  final String? boardId;
  final String? boardSlug;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const FollowTarget({
    required this.targetId,
    required this.targetType,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.canonicalUri,
    this.handle,
    this.did,
    this.actorUri,
    this.inboxUri,
    this.outboxUri,
    this.remoteNodeId,
    this.boardId,
    this.boardSlug,
    this.isDeleted = false,
  });
}
```

Create `follow_edge.dart`:

```dart
import 'follow_target.dart';

enum FollowDirection {
  outbound,
  inbound;

  static FollowDirection parse(String value) => FollowDirection.values.firstWhere(
        (item) => item.name == value,
        orElse: () => throw ArgumentError('Unknown FollowDirection "$value"'),
      );
}

enum FollowStatus {
  pending,
  accepted,
  rejected,
  cancelled,
  blocked,
  failed;

  static FollowStatus parse(String value) => FollowStatus.values.firstWhere(
        (item) => item.name == value,
        orElse: () => throw ArgumentError('Unknown FollowStatus "$value"'),
      );
}

enum FollowVisibility {
  localOnly,
  federated;

  static FollowVisibility parse(String value) => FollowVisibility.values.firstWhere(
        (item) => item.name == value,
        orElse: () => throw ArgumentError('Unknown FollowVisibility "$value"'),
      );
}

class FollowEdge {
  final String followId;
  final String followerDid;
  final String targetId;
  final FollowTargetType targetType;
  final FollowDirection direction;
  final FollowStatus status;
  final FollowVisibility visibility;
  final String? remoteActivityId;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acceptedAt;
  final DateTime? cancelledAt;

  const FollowEdge({
    required this.followId,
    required this.followerDid,
    required this.targetId,
    required this.targetType,
    required this.direction,
    required this.status,
    required this.visibility,
    required this.createdAt,
    required this.updatedAt,
    this.remoteActivityId,
    this.lastError,
    this.acceptedAt,
    this.cancelledAt,
  });
}
```

Create `follow_activity_event.dart`:

```dart
enum FollowActivityEventType {
  followRequested,
  followAccepted,
  followRejected,
  followCancelled,
  followBlocked,
  followFailed,
  followSynced;

  static FollowActivityEventType parse(String value) {
    return FollowActivityEventType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown FollowActivityEventType "$value"'),
    );
  }
}

class FollowActivityEvent {
  final String eventId;
  final String followId;
  final FollowActivityEventType eventType;
  final String actorDid;
  final String? activityId;
  final String? message;
  final DateTime createdAt;

  const FollowActivityEvent({
    required this.eventId,
    required this.followId,
    required this.eventType,
    required this.actorDid,
    required this.createdAt,
    this.activityId,
    this.message,
  });
}
```

Create `outbound_follow_activity.dart`:

```dart
enum OutboundFollowActivityType {
  follow,
  accept,
  reject,
  undo;

  static OutboundFollowActivityType parse(String value) {
    return OutboundFollowActivityType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown OutboundFollowActivityType "$value"'),
    );
  }
}

enum OutboundFollowActivityStatus {
  queued,
  delivering,
  delivered,
  failed;

  static OutboundFollowActivityStatus parse(String value) {
    return OutboundFollowActivityStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown OutboundFollowActivityStatus "$value"'),
    );
  }
}

class OutboundFollowActivity {
  final String outboxId;
  final String activityId;
  final OutboundFollowActivityType activityType;
  final String targetInboxUri;
  final String payloadJson;
  final OutboundFollowActivityStatus status;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deliveredAt;

  const OutboundFollowActivity({
    required this.outboxId,
    required this.activityId,
    required this.activityType,
    required this.targetInboxUri,
    required this.payloadJson,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
    this.deliveredAt,
  });
}
```

- [ ] **Step 3: Add Drift tables**

Create `follow_targets.dart`:

```dart
import 'package:drift/drift.dart';

class FollowTargets extends Table {
  TextColumn get targetId => text()();
  TextColumn get targetType => text()();
  TextColumn get canonicalUri => text().nullable().unique()();
  TextColumn get displayName => text()();
  TextColumn get handle => text().nullable()();
  TextColumn get did => text().nullable()();
  TextColumn get actorUri => text().nullable()();
  TextColumn get inboxUri => text().nullable()();
  TextColumn get outboxUri => text().nullable()();
  TextColumn get remoteNodeId => text().nullable()();
  TextColumn get boardId => text().nullable()();
  TextColumn get boardSlug => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {targetId};
}
```

Create `follow_edges.dart`:

```dart
import 'package:drift/drift.dart';

import 'follow_targets.dart';

class FollowEdges extends Table {
  TextColumn get followId => text()();
  TextColumn get followerDid => text()();
  TextColumn get targetId => text().references(FollowTargets, #targetId)();
  TextColumn get targetType => text()();
  TextColumn get direction => text()();
  TextColumn get status => text()();
  TextColumn get visibility => text()();
  TextColumn get remoteActivityId => text().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get acceptedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {followId};
}
```

Create `follow_activity_events.dart`:

```dart
import 'package:drift/drift.dart';

import 'follow_edges.dart';

class FollowActivityEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get followId => text().references(FollowEdges, #followId)();
  TextColumn get eventType => text()();
  TextColumn get actorDid => text()();
  TextColumn get activityId => text().nullable()();
  TextColumn get message => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {eventId};
}
```

Create `outbound_follow_activities.dart`:

```dart
import 'package:drift/drift.dart';

class OutboundFollowActivities extends Table {
  TextColumn get outboxId => text()();
  TextColumn get activityId => text().unique()();
  TextColumn get activityType => text()();
  TextColumn get targetInboxUri => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deliveredAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {outboxId};
}
```

- [ ] **Step 4: Wire database version and exports**

Modify `ansible_core/store/lib/src/db/app_database.dart`:

```dart
import '../schema/follow_targets.dart';
import '../schema/follow_edges.dart';
import '../schema/follow_activity_events.dart';
import '../schema/outbound_follow_activities.dart';
```

Add the tables to `@DriftDatabase(tables: [...])`:

```dart
    FollowTargets,
    FollowEdges,
    FollowActivityEvents,
    OutboundFollowActivities,
```

Change schema version:

```dart
  int get schemaVersion => 8;
```

Add migration:

```dart
      if (from < 8) {
        await m.createTable(followTargets);
        await m.createTable(followEdges);
        await m.createTable(followActivityEvents);
        await m.createTable(outboundFollowActivities);
      }
```

Modify `ansible_core/store/lib/ansible_store.dart`:

```dart
export 'src/entities/follow_target.dart';
export 'src/entities/follow_edge.dart';
export 'src/entities/follow_activity_event.dart';
export 'src/entities/outbound_follow_activity.dart';
```

Extend the generated database hide list:

```dart
        FollowTarget,
        FollowEdge,
        FollowActivityEvent,
        OutboundFollowActivity;
```

- [ ] **Step 5: Generate Drift code**

Run:

```bash
cd ansible_core/store
dart run build_runner build --delete-conflicting-outputs
```

Expected: PASS and `app_database.g.dart` includes `FollowTargets`, `FollowEdges`, `FollowActivityEvents`, and `OutboundFollowActivities`.

- [ ] **Step 6: Run schema test**

Run:

```bash
cd ansible_core/store
dart test test/drift_follow_repository_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ansible_core/store/lib/src/entities/follow_target.dart ansible_core/store/lib/src/entities/follow_edge.dart ansible_core/store/lib/src/entities/follow_activity_event.dart ansible_core/store/lib/src/entities/outbound_follow_activity.dart ansible_core/store/lib/src/schema/follow_targets.dart ansible_core/store/lib/src/schema/follow_edges.dart ansible_core/store/lib/src/schema/follow_activity_events.dart ansible_core/store/lib/src/schema/outbound_follow_activities.dart ansible_core/store/lib/src/db/app_database.dart ansible_core/store/lib/src/db/app_database.g.dart ansible_core/store/lib/ansible_store.dart ansible_core/store/test/drift_follow_repository_test.dart
git commit -m "feat: add follow store schema"
```

---

## Task 2: Follow Repositories

**Files:**

- Create: `ansible_core/store/lib/src/repositories/follow_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/follow_activity_outbox_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/drift/drift_follow_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/drift/drift_follow_activity_outbox_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/in_memory/in_memory_follow_repository.dart`
- Create: `ansible_core/store/lib/src/repositories/in_memory/in_memory_follow_activity_outbox_repository.dart`
- Modify: `ansible_core/store/lib/ansible_store.dart`
- Test: `ansible_core/store/test/drift_follow_repository_test.dart`
- Test: `ansible_core/store/test/follow_repository_in_memory_test.dart`

- [ ] **Step 1: Expand repository tests first**

Append these tests to `drift_follow_repository_test.dart`:

```dart
import 'package:ansible_store/src/repositories/drift/drift_follow_repository.dart';
import 'package:ansible_store/src/repositories/drift/drift_follow_activity_outbox_repository.dart';
```

Add test setup fields:

```dart
late DriftFollowRepository followRepo;
late DriftFollowActivityOutboxRepository outboxRepo;
```

Initialize them in `setUp`:

```dart
followRepo = DriftFollowRepository(db);
outboxRepo = DriftFollowActivityOutboxRepository(db);
```

Add tests:

```dart
test('upserts target and effective follow edge', () async {
  final now = DateTime.utc(2026, 5, 4);
  final target = FollowTarget(
    targetId: 'target-alice',
    targetType: FollowTargetType.user,
    canonicalUri: 'https://example.social/users/alice',
    displayName: 'Alice',
    did: 'did:key:alice',
    actorUri: 'https://example.social/users/alice',
    inboxUri: 'https://example.social/users/alice/inbox',
    createdAt: now,
    updatedAt: now,
  );
  await followRepo.upsertTarget(target);

  final edge = FollowEdge(
    followId: 'follow-1',
    followerDid: 'did:key:local',
    targetId: target.targetId,
    targetType: FollowTargetType.user,
    direction: FollowDirection.outbound,
    status: FollowStatus.pending,
    visibility: FollowVisibility.federated,
    remoteActivityId: 'https://node.example/activities/follow/1',
    createdAt: now,
    updatedAt: now,
  );
  await followRepo.upsertEdge(edge);

  final loadedTarget = await followRepo.getTargetByCanonicalUri(target.canonicalUri!);
  final loadedEdge = await followRepo.getEdge(
    edge.followerDid,
    target.targetId,
    FollowDirection.outbound,
  );

  expect(loadedTarget!.displayName, 'Alice');
  expect(loadedEdge!.status, FollowStatus.pending);
});

test('lists following by target type', () async {
  final now = DateTime.utc(2026, 5, 4);
  await followRepo.upsertTarget(FollowTarget(
    targetId: 'board-1-target',
    targetType: FollowTargetType.board,
    canonicalUri: 'local://boards/board-1',
    displayName: 'Civic Tech',
    boardId: 'board-1',
    boardSlug: 'civic-tech',
    createdAt: now,
    updatedAt: now,
  ));
  await followRepo.upsertEdge(FollowEdge(
    followId: 'follow-board-1',
    followerDid: 'did:key:local',
    targetId: 'board-1-target',
    targetType: FollowTargetType.board,
    direction: FollowDirection.outbound,
    status: FollowStatus.accepted,
    visibility: FollowVisibility.localOnly,
    createdAt: now,
    updatedAt: now,
    acceptedAt: now,
  ));

  final boards = await followRepo.listFollowing(
    'did:key:local',
    targetType: FollowTargetType.board,
  );

  expect(boards, hasLength(1));
  expect(boards.single.targetId, 'board-1-target');
});

test('records follow activity events', () async {
  final now = DateTime.utc(2026, 5, 4);
  await followRepo.recordEvent(FollowActivityEvent(
    eventId: 'event-1',
    followId: 'follow-1',
    eventType: FollowActivityEventType.followRequested,
    actorDid: 'did:key:local',
    activityId: 'https://node.example/activities/follow/1',
    createdAt: now,
  ));

  final events = await followRepo.listEvents('follow-1');

  expect(events.single.eventType, FollowActivityEventType.followRequested);
});

test('queues and marks outbound follow activities', () async {
  final now = DateTime.utc(2026, 5, 4);
  await outboxRepo.enqueue(OutboundFollowActivity(
    outboxId: 'outbox-1',
    activityId: 'https://node.example/activities/follow/1',
    activityType: OutboundFollowActivityType.follow,
    targetInboxUri: 'https://example.social/users/alice/inbox',
    payloadJson: '{"type":"Follow"}',
    status: OutboundFollowActivityStatus.queued,
    attemptCount: 0,
    createdAt: now,
    updatedAt: now,
  ));

  expect(await outboxRepo.listQueued(), hasLength(1));

  await outboxRepo.markDelivering('outbox-1', now.add(const Duration(seconds: 1)));
  await outboxRepo.markDelivered('outbox-1', now.add(const Duration(seconds: 2)));

  expect(await outboxRepo.listQueued(), isEmpty);
});
```

Create `follow_repository_in_memory_test.dart` with the same behavior using `InMemoryFollowRepository` and `InMemoryFollowActivityOutboxRepository`.

Run:

```bash
cd ansible_core/store
dart test test/drift_follow_repository_test.dart test/follow_repository_in_memory_test.dart
```

Expected: FAIL because repository classes do not exist.

- [ ] **Step 2: Add repository interfaces**

Create `follow_repository.dart`:

```dart
import '../entities/follow_activity_event.dart';
import '../entities/follow_edge.dart';
import '../entities/follow_target.dart';

abstract class FollowRepository {
  Future<FollowTarget?> getTarget(String targetId);
  Future<FollowTarget?> getTargetByCanonicalUri(String canonicalUri);
  Future<FollowTarget?> getBoardTarget(String remoteNodeId, String boardId);
  Future<void> upsertTarget(FollowTarget target);
  Future<FollowEdge?> getEdge(
    String followerDid,
    String targetId,
    FollowDirection direction,
  );
  Future<List<FollowEdge>> listFollowing(
    String followerDid, {
    FollowTargetType? targetType,
  });
  Future<List<FollowEdge>> listFollowers(String targetId);
  Future<void> upsertEdge(FollowEdge edge);
  Future<void> updateEdgeStatus(
    String followId,
    FollowStatus status,
    DateTime now, {
    String? lastError,
  });
  Future<void> recordEvent(FollowActivityEvent event);
  Future<List<FollowActivityEvent>> listEvents(String followId);
}
```

Create `follow_activity_outbox_repository.dart`:

```dart
import '../entities/outbound_follow_activity.dart';

abstract class FollowActivityOutboxRepository {
  Future<void> enqueue(OutboundFollowActivity activity);
  Future<List<OutboundFollowActivity>> listQueued({int limit = 50});
  Future<void> markDelivering(String outboxId, DateTime now);
  Future<void> markDelivered(String outboxId, DateTime now);
  Future<void> markFailed(String outboxId, String lastError, DateTime now);
}
```

- [ ] **Step 3: Implement Drift repositories**

Implement `DriftFollowRepository` using `InsertMode.insertOrReplace`, row mappers, and queries ordered by `updatedAt DESC`.

Use this status update pattern:

```dart
@override
Future<void> updateEdgeStatus(
  String followId,
  FollowStatus status,
  DateTime now, {
  String? lastError,
}) async {
  await (_db.update(_db.followEdges)..where((t) => t.followId.equals(followId))).write(
    FollowEdgesCompanion(
      status: Value(status.name),
      updatedAt: Value(now),
      acceptedAt: status == FollowStatus.accepted ? Value(now) : const Value.absent(),
      cancelledAt: status == FollowStatus.cancelled ? Value(now) : const Value.absent(),
      lastError: Value(lastError),
    ),
  );
}
```

Implement `DriftFollowActivityOutboxRepository` with `listQueued`:

```dart
@override
Future<List<entity.OutboundFollowActivity>> listQueued({int limit = 50}) async {
  final rows = await (_db.select(_db.outboundFollowActivities)
        ..where((t) => t.status.equals(entity.OutboundFollowActivityStatus.queued.name))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
        ..limit(limit))
      .get();
  return rows.map(_mapRowToEntity).toList();
}
```

- [ ] **Step 4: Implement in-memory repositories**

Implement `InMemoryFollowRepository` with maps:

```dart
final Map<String, FollowTarget> _targets = {};
final Map<String, FollowEdge> _edges = {};
final Map<String, List<FollowActivityEvent>> _eventsByFollow = {};
```

Implement `getEdge` by scanning `_edges.values` for `followerDid`, `targetId`, and `direction`.

Implement `InMemoryFollowActivityOutboxRepository` with:

```dart
final Map<String, OutboundFollowActivity> _activities = {};
```

Return queued records sorted by `createdAt`.

- [ ] **Step 5: Export repositories**

Modify `ansible_core/store/lib/ansible_store.dart`:

```dart
export 'src/repositories/follow_repository.dart';
export 'src/repositories/follow_activity_outbox_repository.dart';
export 'src/repositories/in_memory/in_memory_follow_repository.dart';
export 'src/repositories/in_memory/in_memory_follow_activity_outbox_repository.dart';
export 'src/repositories/drift/drift_follow_repository.dart';
export 'src/repositories/drift/drift_follow_activity_outbox_repository.dart';
```

- [ ] **Step 6: Run repository tests**

Run:

```bash
cd ansible_core/store
dart test test/drift_follow_repository_test.dart test/follow_repository_in_memory_test.dart
dart analyze
```

Expected: PASS and no analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add ansible_core/store/lib/src/repositories/follow_repository.dart ansible_core/store/lib/src/repositories/follow_activity_outbox_repository.dart ansible_core/store/lib/src/repositories/drift/drift_follow_repository.dart ansible_core/store/lib/src/repositories/drift/drift_follow_activity_outbox_repository.dart ansible_core/store/lib/src/repositories/in_memory/in_memory_follow_repository.dart ansible_core/store/lib/src/repositories/in_memory/in_memory_follow_activity_outbox_repository.dart ansible_core/store/lib/ansible_store.dart ansible_core/store/test/drift_follow_repository_test.dart ansible_core/store/test/follow_repository_in_memory_test.dart
git commit -m "feat: add follow repositories"
```

---

## Task 3: ActivityPub Follow Models

**Files:**

- Create: `ansible_core/ap/lib/src/follow_activities.dart`
- Modify: `ansible_core/ap/lib/ansible_ap.dart`
- Test: `ansible_core/ap/test/follow_activities_test.dart`

- [ ] **Step 1: Write failing AP protocol tests**

Create `ansible_core/ap/test/follow_activities_test.dart`:

```dart
import 'package:ansible_ap/ansible_ap.dart';
import 'package:test/test.dart';

void main() {
  group('FollowActivity', () {
    test('serializes user follow', () {
      final activity = FollowActivity.user(
        id: 'https://node.example/activities/follow/1',
        actor: 'did:key:local',
        object: 'https://remote.example/users/alice',
        published: DateTime.utc(2026, 5, 4),
      );

      expect(activity.toJson(), containsPair('type', 'Follow'));
      expect(activity.toJson(), containsPair('actor', 'did:key:local'));
      expect(activity.toJson(), containsPair('object', 'https://remote.example/users/alice'));
    });

    test('serializes board follow extension', () {
      final activity = FollowActivity.board(
        id: 'https://node.example/activities/follow/board-1',
        actor: 'did:key:local',
        object: 'https://remote.example/boards/civic-tech',
        boardId: 'board-civic-tech',
        published: DateTime.utc(2026, 5, 4),
      );

      final json = activity.toJson();

      expect(json['type'], 'Follow');
      expect(json['trisAura:targetType'], 'board');
      expect(json['trisAura:boardId'], 'board-civic-tech');
    });

    test('rejects malformed inbound activity', () {
      expect(
        () => FollowActivity.fromJson({'type': 'Follow', 'actor': 'did:key:local'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

Run:

```bash
cd ansible_core/ap
dart test test/follow_activities_test.dart
```

Expected: FAIL because `FollowActivity` does not exist.

- [ ] **Step 2: Implement follow activity models**

Create `follow_activities.dart`:

```dart
class FollowActivity {
  final String id;
  final String actor;
  final String object;
  final DateTime published;
  final bool isBoardFollow;
  final String? boardId;

  const FollowActivity({
    required this.id,
    required this.actor,
    required this.object,
    required this.published,
    this.isBoardFollow = false,
    this.boardId,
  });

  factory FollowActivity.user({
    required String id,
    required String actor,
    required String object,
    required DateTime published,
  }) {
    return FollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: published,
    );
  }

  factory FollowActivity.board({
    required String id,
    required String actor,
    required String object,
    required String boardId,
    required DateTime published,
  }) {
    return FollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: published,
      isBoardFollow: true,
      boardId: boardId,
    );
  }

  factory FollowActivity.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'Follow') {
      throw const FormatException('Activity type must be Follow.');
    }
    final id = json['id'];
    final actor = json['actor'];
    final object = json['object'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Follow id is required.');
    }
    if (actor is! String || actor.isEmpty) {
      throw const FormatException('Follow actor is required.');
    }
    if (object is! String || object.isEmpty) {
      throw const FormatException('Follow object is required.');
    }
    return FollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: DateTime.parse(json['published'] as String).toUtc(),
      isBoardFollow: json['trisAura:targetType'] == 'board',
      boardId: json['trisAura:boardId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      '@context': isBoardFollow
          ? ['https://www.w3.org/ns/activitystreams', 'https://trisaura.io/ns/follow']
          : 'https://www.w3.org/ns/activitystreams',
      'id': id,
      'type': 'Follow',
      'actor': actor,
      'object': object,
      'to': [object],
      'published': published.toIso8601String(),
    };
    if (isBoardFollow) {
      map['trisAura:targetType'] = 'board';
      map['trisAura:boardId'] = boardId;
    }
    return map;
  }
}
```

In the same file, add `FollowResponseActivity` for `Accept` and `Reject`, plus `UndoFollowActivity`. Use `object` as nested JSON and validate `id`, `type`, `actor`, and `object`.

- [ ] **Step 3: Export AP models**

Modify `ansible_core/ap/lib/ansible_ap.dart`:

```dart
export 'src/follow_activities.dart';
```

- [ ] **Step 4: Run AP tests**

Run:

```bash
cd ansible_core/ap
dart test
dart analyze
```

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add ansible_core/ap/lib/src/follow_activities.dart ansible_core/ap/lib/ansible_ap.dart ansible_core/ap/test/follow_activities_test.dart
git commit -m "feat: add ActivityPub follow models"
```

---

## Task 4: Domain Follow Service

**Files:**

- Create: `ansible_core/domain/lib/src/follow/follow_result.dart`
- Create: `ansible_core/domain/lib/src/follow/follow_service.dart`
- Modify: `ansible_core/domain/lib/ansible_domain.dart`
- Test: `ansible_core/domain/test/follow_service_test.dart`

- [ ] **Step 1: Write failing domain tests**

Create `ansible_core/domain/test/follow_service_test.dart`:

```dart
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('FollowService', () {
    late InMemoryFollowRepository followRepo;
    late InMemoryFollowActivityOutboxRepository outboxRepo;
    late InMemoryBoardSyncConfigRepository boardSyncRepo;
    late FollowService service;

    setUp(() {
      followRepo = InMemoryFollowRepository();
      outboxRepo = InMemoryFollowActivityOutboxRepository();
      boardSyncRepo = InMemoryBoardSyncConfigRepository();
      service = FollowService(
        followRepository: followRepo,
        outboxRepository: outboxRepo,
        boardSyncConfigRepository: boardSyncRepo,
        idFactory: _SequenceIds(),
      );
    });

    test('follow local user creates accepted local edge', () async {
      final result = await service.followUser(
        followerDid: 'did:key:local',
        targetDid: 'did:key:alice',
        displayName: 'Alice',
        now: DateTime.utc(2026, 5, 4),
      );

      expect(result.status, FollowResultStatus.success);
      final edges = await followRepo.listFollowing('did:key:local');
      expect(edges.single.status, FollowStatus.accepted);
      expect(edges.single.visibility, FollowVisibility.localOnly);
    });

    test('follow remote user queues federated Follow', () async {
      await service.followUser(
        followerDid: 'did:key:local',
        actorUri: 'https://remote.example/users/alice',
        inboxUri: 'https://remote.example/users/alice/inbox',
        displayName: 'Alice',
        now: DateTime.utc(2026, 5, 4),
      );

      final edges = await followRepo.listFollowing('did:key:local');
      final outbox = await outboxRepo.listQueued();

      expect(edges.single.status, FollowStatus.pending);
      expect(outbox.single.activityType, OutboundFollowActivityType.follow);
    });

    test('follow remote board enables board sync config', () async {
      await service.followBoard(
        followerDid: 'did:key:local',
        remoteNodeId: 'remote-1',
        boardId: 'board-1',
        boardSlug: 'civic-tech',
        displayName: 'Civic Tech',
        now: DateTime.utc(2026, 5, 4),
      );

      final config = await boardSyncRepo.getByRemoteAndBoard('remote-1', 'board-1');
      expect(config!.syncEnabled, isTrue);
    });
  });
}

class _SequenceIds implements FollowIdFactory {
  var _next = 0;

  @override
  String next(String prefix) {
    _next += 1;
    return '$prefix-$_next';
  }
}
```

Run:

```bash
cd ansible_core/domain
dart test test/follow_service_test.dart
```

Expected: FAIL because `FollowService`, `FollowResultStatus`, and `FollowIdFactory` do not exist. If `InMemoryBoardSyncConfigRepository` does not exist, create it in Task 4 Step 2 before completing the test.

- [ ] **Step 2: Add missing in-memory board sync repository if absent**

If `ansible_core/store/lib/src/repositories/in_memory/in_memory_board_sync_config_repository.dart` is absent, create it:

```dart
import '../../entities/board_sync_config.dart';
import '../board_sync_config_repository.dart';

class InMemoryBoardSyncConfigRepository implements BoardSyncConfigRepository {
  final Map<String, BoardSyncConfig> _configs = {};

  @override
  Future<void> create(BoardSyncConfig config) async {
    _configs[config.id] = config;
  }

  @override
  Future<BoardSyncConfig?> getById(String id) async => _configs[id];

  @override
  Future<BoardSyncConfig?> getByRemoteAndBoard(String remoteNodeId, String boardId) async {
    return _configs.values
        .where((config) => config.remoteNodeId == remoteNodeId && config.boardId == boardId)
        .cast<BoardSyncConfig?>()
        .firstWhere((config) => config != null, orElse: () => null);
  }

  @override
  Future<List<BoardSyncConfig>> listByRemote(String remoteNodeId) async {
    return _configs.values.where((config) => config.remoteNodeId == remoteNodeId).toList();
  }

  @override
  Future<List<String>> getEnabledBoardIds(String remoteNodeId) async {
    return _configs.values
        .where((config) => config.remoteNodeId == remoteNodeId && config.syncEnabled)
        .map((config) => config.boardId)
        .toList();
  }

  @override
  Future<void> update(BoardSyncConfig config) async {
    _configs[config.id] = config;
  }

  @override
  Future<void> delete(String id) async {
    _configs.remove(id);
  }

  @override
  Future<void> toggleSync(String remoteNodeId, String boardId, bool enabled) async {
    final existing = await getByRemoteAndBoard(remoteNodeId, boardId);
    final now = DateTime.now().toUtc();
    if (existing == null) {
      await create(BoardSyncConfig(
        id: '${remoteNodeId}_$boardId',
        remoteNodeId: remoteNodeId,
        boardId: boardId,
        syncEnabled: enabled,
        createdAt: now,
        updatedAt: now,
      ));
      return;
    }
    await update(existing.copyWith(syncEnabled: enabled, updatedAt: now));
  }
}
```

Export it from `ansible_store.dart`.

- [ ] **Step 3: Implement result types**

Create `follow_result.dart`:

```dart
enum FollowResultStatus {
  success,
  duplicate,
  targetNotFound,
  failed;
}

class FollowResult {
  final FollowResultStatus status;
  final String? followId;
  final String? message;

  const FollowResult._({
    required this.status,
    this.followId,
    this.message,
  });

  const FollowResult.success(String followId)
      : this._(status: FollowResultStatus.success, followId: followId);

  const FollowResult.duplicate(String followId)
      : this._(status: FollowResultStatus.duplicate, followId: followId);

  const FollowResult.targetNotFound(String message)
      : this._(status: FollowResultStatus.targetNotFound, message: message);

  const FollowResult.failed(String message)
      : this._(status: FollowResultStatus.failed, message: message);
}
```

- [ ] **Step 4: Implement `FollowService`**

Create `follow_service.dart` with constructor:

```dart
import 'dart:convert';

import 'package:ansible_ap/ansible_ap.dart';
import 'package:ansible_store/ansible_store.dart';

import 'follow_result.dart';

abstract class FollowIdFactory {
  String next(String prefix);
}

class UtcTimestampFollowIdFactory implements FollowIdFactory {
  @override
  String next(String prefix) => '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}';
}

class FollowService {
  final FollowRepository followRepository;
  final FollowActivityOutboxRepository outboxRepository;
  final BoardSyncConfigRepository boardSyncConfigRepository;
  final FollowIdFactory idFactory;

  FollowService({
    required this.followRepository,
    required this.outboxRepository,
    required this.boardSyncConfigRepository,
    FollowIdFactory? idFactory,
  }) : idFactory = idFactory ?? UtcTimestampFollowIdFactory();
}
```

Add `followUser`:

```dart
Future<FollowResult> followUser({
  required String followerDid,
  String? targetDid,
  String? actorUri,
  String? inboxUri,
  required String displayName,
  required DateTime now,
}) async {
  final canonicalUri = actorUri ?? targetDid;
  if (canonicalUri == null || canonicalUri.isEmpty) {
    return const FollowResult.targetNotFound('target_not_found');
  }

  final existingTarget = await followRepository.getTargetByCanonicalUri(canonicalUri);
  final targetId = existingTarget?.targetId ?? idFactory.next('follow-target');
  final target = FollowTarget(
    targetId: targetId,
    targetType: FollowTargetType.user,
    canonicalUri: canonicalUri,
    displayName: displayName,
    did: targetDid,
    actorUri: actorUri,
    inboxUri: inboxUri,
    createdAt: existingTarget?.createdAt ?? now,
    updatedAt: now,
  );
  await followRepository.upsertTarget(target);

  final existingEdge = await followRepository.getEdge(followerDid, targetId, FollowDirection.outbound);
  if (existingEdge != null && existingEdge.status != FollowStatus.cancelled) {
    return FollowResult.duplicate(existingEdge.followId);
  }

  final federated = inboxUri != null && inboxUri.isNotEmpty;
  final followId = existingEdge?.followId ?? idFactory.next('follow');
  final activityId = federated ? 'local://activities/follow/$followId' : null;
  await followRepository.upsertEdge(FollowEdge(
    followId: followId,
    followerDid: followerDid,
    targetId: targetId,
    targetType: FollowTargetType.user,
    direction: FollowDirection.outbound,
    status: federated ? FollowStatus.pending : FollowStatus.accepted,
    visibility: federated ? FollowVisibility.federated : FollowVisibility.localOnly,
    remoteActivityId: activityId,
    createdAt: existingEdge?.createdAt ?? now,
    updatedAt: now,
    acceptedAt: federated ? null : now,
  ));

  if (federated) {
    final activity = FollowActivity.user(
      id: activityId!,
      actor: followerDid,
      object: actorUri!,
      published: now,
    );
    await outboxRepository.enqueue(OutboundFollowActivity(
      outboxId: idFactory.next('follow-outbox'),
      activityId: activityId,
      activityType: OutboundFollowActivityType.follow,
      targetInboxUri: inboxUri,
      payloadJson: jsonEncode(activity.toJson()),
      status: OutboundFollowActivityStatus.queued,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    ));
  }

  await followRepository.recordEvent(FollowActivityEvent(
    eventId: idFactory.next('follow-event'),
    followId: followId,
    eventType: FollowActivityEventType.followRequested,
    actorDid: followerDid,
    activityId: activityId,
    createdAt: now,
  ));

  return FollowResult.success(followId);
}
```

Add `followBoard`, `acceptFollow`, `rejectFollow`, `unfollow`, `blockTarget`, and `retryFollow` using the same pattern:

- `followBoard` creates `FollowTargetType.board`; remote board means `remoteNodeId != null`; call `boardSyncConfigRepository.toggleSync(remoteNodeId, boardId, true)`.
- `unfollow` sets `FollowStatus.cancelled`; remote board means call `toggleSync(remoteNodeId, boardId, false)`; federated edge means enqueue `OutboundFollowActivityType.undo`.
- `acceptFollow` sets `FollowStatus.accepted` and records `followAccepted`.
- `rejectFollow` sets `FollowStatus.rejected` and records `followRejected`.
- `blockTarget` sets `FollowStatus.blocked` and records `followBlocked`.
- `retryFollow` changes `failed` back to `pending` and enqueues a new outbound activity for targets with an inbox.

- [ ] **Step 5: Export domain service**

Modify `ansible_core/domain/lib/ansible_domain.dart`:

```dart
export 'src/follow/follow_result.dart';
export 'src/follow/follow_service.dart';
```

- [ ] **Step 6: Run tests**

Run:

```bash
cd ansible_core/domain
dart test test/follow_service_test.dart
dart analyze
```

Expected: PASS and no analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add ansible_core/domain/lib/src/follow/follow_result.dart ansible_core/domain/lib/src/follow/follow_service.dart ansible_core/domain/lib/ansible_domain.dart ansible_core/domain/test/follow_service_test.dart ansible_core/store/lib/src/repositories/in_memory/in_memory_board_sync_config_repository.dart ansible_core/store/lib/ansible_store.dart
git commit -m "feat: add follow domain service"
```

---

## Task 5: Following Feed Projector

**Files:**

- Create: `ansible_core/domain/lib/src/follow/follow_feed_projector.dart`
- Modify: `ansible_core/domain/lib/ansible_domain.dart`
- Test: `ansible_core/domain/test/follow_feed_projector_test.dart`

- [ ] **Step 1: Write failing feed projector tests**

Create `follow_feed_projector_test.dart`:

```dart
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  group('FollowFeedProjector', () {
    test('deduplicates posts matching followed user and board', () async {
      final followRepo = InMemoryFollowRepository();
      final boardRepo = InMemoryBoardRepository();
      final threadRepo = InMemoryThreadRepository();
      final postRepo = InMemoryPostRepository();
      final now = DateTime.utc(2026, 5, 4);

      await boardRepo.create(Board(
        id: 'board-1',
        slug: 'civic-tech',
        title: 'Civic Tech',
        createdAt: now,
        updatedAt: now,
      ));
      await threadRepo.create(Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'Hello',
        authorId: 'did:key:alice',
        createdAt: now,
        updatedAt: now,
      ));
      await postRepo.create(Post(
        id: 'post-1',
        threadId: 'thread-1',
        boardId: 'board-1',
        authorId: 'did:key:alice',
        content: 'Hello world',
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
      ));

      await followRepo.upsertTarget(FollowTarget(
        targetId: 'target-alice',
        targetType: FollowTargetType.user,
        canonicalUri: 'did:key:alice',
        displayName: 'Alice',
        did: 'did:key:alice',
        createdAt: now,
        updatedAt: now,
      ));
      await followRepo.upsertTarget(FollowTarget(
        targetId: 'target-board-1',
        targetType: FollowTargetType.board,
        canonicalUri: 'local://boards/board-1',
        displayName: 'Civic Tech',
        boardId: 'board-1',
        createdAt: now,
        updatedAt: now,
      ));
      await followRepo.upsertEdge(FollowEdge(
        followId: 'follow-user',
        followerDid: 'did:key:local',
        targetId: 'target-alice',
        targetType: FollowTargetType.user,
        direction: FollowDirection.outbound,
        status: FollowStatus.accepted,
        visibility: FollowVisibility.localOnly,
        createdAt: now,
        updatedAt: now,
        acceptedAt: now,
      ));
      await followRepo.upsertEdge(FollowEdge(
        followId: 'follow-board',
        followerDid: 'did:key:local',
        targetId: 'target-board-1',
        targetType: FollowTargetType.board,
        direction: FollowDirection.outbound,
        status: FollowStatus.accepted,
        visibility: FollowVisibility.localOnly,
        createdAt: now,
        updatedAt: now,
        acceptedAt: now,
      ));

      final projector = FollowFeedProjector(
        followRepository: followRepo,
        boardRepository: boardRepo,
        threadRepository: threadRepo,
        postRepository: postRepo,
      );

      final entries = await projector.project(followerDid: 'did:key:local');

      expect(entries, hasLength(1));
      expect(entries.single.post.id, 'post-1');
      expect(entries.single.reasons, contains(FollowFeedReason.followedUser));
      expect(entries.single.reasons, contains(FollowFeedReason.followedBoard));
    });
  });
}
```

Run:

```bash
cd ansible_core/domain
dart test test/follow_feed_projector_test.dart
```

Expected: FAIL because `FollowFeedProjector` does not exist.

- [ ] **Step 2: Implement feed projection models**

Create `follow_feed_projector.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';

enum FollowFeedReason {
  followedUser,
  followedBoard,
}

class FollowFeedEntry {
  final Post post;
  final Thread thread;
  final Board? board;
  final Set<FollowFeedReason> reasons;

  const FollowFeedEntry({
    required this.post,
    required this.thread,
    required this.board,
    required this.reasons,
  });
}
```

- [ ] **Step 3: Implement projector**

Add:

```dart
class FollowFeedProjector {
  final FollowRepository followRepository;
  final BoardRepository boardRepository;
  final ThreadRepository threadRepository;
  final PostRepository postRepository;

  FollowFeedProjector({
    required this.followRepository,
    required this.boardRepository,
    required this.threadRepository,
    required this.postRepository,
  });

  Future<List<FollowFeedEntry>> project({required String followerDid}) async {
    final followedUsers = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.user,
    );
    final followedBoards = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.board,
    );

    final followedUserDids = <String>{};
    for (final edge in followedUsers.where((edge) => edge.status == FollowStatus.accepted)) {
      final target = await followRepository.getTarget(edge.targetId);
      final did = target?.did ?? target?.canonicalUri;
      if (did != null) followedUserDids.add(did);
    }

    final followedBoardIds = <String>{};
    for (final edge in followedBoards.where((edge) => edge.status == FollowStatus.accepted)) {
      final target = await followRepository.getTarget(edge.targetId);
      if (target?.boardId != null) followedBoardIds.add(target!.boardId!);
    }

    final threads = await threadRepository.list();
    final boards = await boardRepository.list();
    final boardById = {for (final board in boards) board.id: board};
    final entriesByPostId = <String, FollowFeedEntry>{};

    for (final thread in threads) {
      final posts = await postRepository.list(threadId: thread.id);
      for (final post in posts.where((post) => !post.isDeleted)) {
        final reasons = <FollowFeedReason>{};
        if (followedUserDids.contains(post.authorId)) {
          reasons.add(FollowFeedReason.followedUser);
        }
        if (followedBoardIds.contains(post.boardId)) {
          reasons.add(FollowFeedReason.followedBoard);
        }
        if (reasons.isEmpty) continue;

        entriesByPostId[post.id] = FollowFeedEntry(
          post: post,
          thread: thread,
          board: boardById[post.boardId],
          reasons: reasons,
        );
      }
    }

    final entries = entriesByPostId.values.toList()
      ..sort((a, b) {
        final byEdit = b.post.lastEditAt.compareTo(a.post.lastEditAt);
        if (byEdit != 0) return byEdit;
        return b.post.createdAt.compareTo(a.post.createdAt);
      });
    return entries;
  }
}
```

- [ ] **Step 4: Export projector**

Modify `ansible_core/domain/lib/ansible_domain.dart`:

```dart
export 'src/follow/follow_feed_projector.dart';
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd ansible_core/domain
dart test test/follow_feed_projector_test.dart
dart analyze
```

Expected: PASS and no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add ansible_core/domain/lib/src/follow/follow_feed_projector.dart ansible_core/domain/lib/ansible_domain.dart ansible_core/domain/test/follow_feed_projector_test.dart
git commit -m "feat: add following feed projector"
```

---

## Task 6: Sync Inbox And Outbox Delivery

**Files:**

- Create: `ansible_sync/handlers/lib/src/controllers/follow_inbox_controller.dart`
- Modify: `ansible_sync/handlers/lib/ansible_sync.dart`
- Test: `ansible_sync/handlers/test/follow_inbox_controller_test.dart`

- [ ] **Step 1: Write failing inbox tests**

Create `follow_inbox_controller_test.dart`:

```dart
import 'dart:convert';

import 'package:ansible_sync/ansible_sync.dart';
import 'package:test/test.dart';

void main() {
  group('FollowInboxController', () {
    test('rejects malformed follow without object', () async {
      final controller = FollowInboxController();
      final response = await controller.handleJson({
        'id': 'https://remote.example/activities/follow/1',
        'type': 'Follow',
        'actor': 'https://remote.example/users/alice',
      });

      expect(response.statusCode, 400);
      expect(jsonDecode(response.body)['error'], 'invalid_follow_activity');
    });
  });
}
```

Run:

```bash
cd ansible_sync/handlers
dart test test/follow_inbox_controller_test.dart
```

Expected: FAIL because `FollowInboxController` does not exist.

- [ ] **Step 2: Implement controller shell**

Create `follow_inbox_controller.dart`:

```dart
import 'dart:convert';

import 'package:ansible_ap/ansible_ap.dart';
import 'package:shelf/shelf.dart';

class FollowInboxController {
  Future<Response> handleJson(Map<String, dynamic> json) async {
    try {
      final type = json['type'];
      if (type == 'Follow') {
        FollowActivity.fromJson(json);
        return Response.ok(jsonEncode({'status': 'accepted'}));
      }
      return Response(400, body: jsonEncode({'error': 'unsupported_follow_activity'}));
    } on FormatException {
      return Response(400, body: jsonEncode({'error': 'invalid_follow_activity'}));
    }
  }
}
```

Export from `ansible_sync/handlers/lib/ansible_sync.dart`:

```dart
export 'src/controllers/follow_inbox_controller.dart';
```

- [ ] **Step 3: Add service-backed constructor**

After shell tests pass, add optional dependencies:

```dart
class FollowInboxController {
  final FollowService? followService;

  FollowInboxController({this.followService});
}
```

When `followService` is non-null, route valid `Follow`, `Accept`, `Reject`, and `Undo` activities to service methods. Keep `handleJson` available for tests.

- [ ] **Step 4: Run sync tests**

Run:

```bash
cd ansible_sync/handlers
dart test
dart analyze
```

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add ansible_sync/handlers/lib/src/controllers/follow_inbox_controller.dart ansible_sync/handlers/lib/ansible_sync.dart ansible_sync/handlers/test/follow_inbox_controller_test.dart
git commit -m "feat: route follow inbox activities"
```

---

## Task 7: Flutter Follow Controls And Following Feed Filter

**Files:**

- Create: `ansible_node/app/lib/widgets/follow_button.dart`
- Create: `ansible_node/app/lib/widgets/feed_filter_tabs.dart`
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Modify: `ansible_node/app/lib/screens/boards_list_screen.dart`
- Test: `ansible_node/app/test/follow_button_test.dart`
- Test: `ansible_node/app/test/following_feed_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `follow_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ansible_node/widgets/follow_button.dart';

void main() {
  testWidgets('follow button displays status label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowButton(
            status: FollowButtonStatus.notFollowing,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Follow'), findsOneWidget);
  });
}
```

Run:

```bash
cd ansible_node/app
flutter test test/follow_button_test.dart
```

Expected: FAIL because `FollowButton` does not exist.

- [ ] **Step 2: Implement `FollowButton`**

Create `follow_button.dart`:

```dart
import 'package:flutter/material.dart';

enum FollowButtonStatus {
  notFollowing,
  requested,
  following,
  failed,
  blocked,
}

class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.status,
    required this.onPressed,
  });

  final FollowButtonStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      FollowButtonStatus.notFollowing => 'Follow',
      FollowButtonStatus.requested => 'Requested',
      FollowButtonStatus.following => 'Following',
      FollowButtonStatus.failed => 'Retry',
      FollowButtonStatus.blocked => 'Blocked',
    };
    return FilledButton.tonal(
      onPressed: status == FollowButtonStatus.blocked ? null : onPressed,
      child: Text(label),
    );
  }
}
```

- [ ] **Step 3: Implement feed filter tabs**

Create `feed_filter_tabs.dart`:

```dart
import 'package:flutter/material.dart';

enum FeedFilter {
  all,
  following,
  boards,
}

class FeedFilterTabs extends StatelessWidget {
  const FeedFilterTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final FeedFilter selected;
  final ValueChanged<FeedFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FeedFilter>(
      segments: const [
        ButtonSegment(value: FeedFilter.all, label: Text('All')),
        ButtonSegment(value: FeedFilter.following, label: Text('Following')),
        ButtonSegment(value: FeedFilter.boards, label: Text('Boards')),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}
```

- [ ] **Step 4: Wire HomeShell feed filter**

Modify `home_shell.dart`:

```dart
import '../widgets/feed_filter_tabs.dart';
```

Add field:

```dart
FeedFilter _feedFilter = FeedFilter.all;
```

Add repositories:

```dart
late final DriftFollowRepository _followRepo;
```

Initialize:

```dart
_followRepo = DriftFollowRepository(widget.db);
```

In `_loadData`, when `_feedFilter == FeedFilter.following`, use `FollowFeedProjector` with Drift repositories to obtain entries and map them to `PostCardData`. Keep current behavior for `FeedFilter.all` and selected board views.

Add `FeedFilterTabs` near the top controls:

```dart
FeedFilterTabs(
  selected: _feedFilter,
  onChanged: (filter) {
    setState(() {
      _feedFilter = filter;
      if (filter == FeedFilter.following) {
        _selectedBoardId = null;
      }
    });
    _loadData();
  },
),
```

- [ ] **Step 5: Wire board follow button**

In `boards_list_screen.dart`, instantiate `DriftFollowRepository` and `FollowService`. Add a trailing `FollowButton` for each board. For local boards, call:

```dart
await _followService.followBoard(
  followerDid: 'did:key:local',
  boardId: board.id,
  boardSlug: board.slug,
  displayName: board.title,
  now: DateTime.now().toUtc(),
);
```

After the call, refresh local state.

- [ ] **Step 6: Run app tests**

Run:

```bash
cd ansible_node/app
flutter test test/follow_button_test.dart test/following_feed_test.dart
flutter test
flutter analyze --no-fatal-infos
```

Expected: PASS. Info-level analyzer messages may remain from existing code, but no errors or warnings should remain.

- [ ] **Step 7: Commit**

```bash
git add ansible_node/app/lib/widgets/follow_button.dart ansible_node/app/lib/widgets/feed_filter_tabs.dart ansible_node/app/lib/screens/home_shell.dart ansible_node/app/lib/screens/boards_list_screen.dart ansible_node/app/test/follow_button_test.dart ansible_node/app/test/following_feed_test.dart
git commit -m "feat: add follow controls and following feed"
```

---

## Task 8: Full Verification And Documentation Update

**Files:**

- Modify: `README.md`
- Modify: `docs/protocol/ansible_sync_spec_v0.1.md`
- Modify: `docs/superpowers/specs/2026-05-04-follow-users-boards-design.md` if implementation changes the public behavior described there

- [ ] **Step 1: Add README feature status**

Add this under the docs list or a new feature status section:

```markdown
## Social Graph Direction

Follow users and follow boards are implemented as a local-first social
subscription layer. User follows build a Following feed from accepted actor
relationships. Board follows build the same feed from accepted board
relationships and remote board follows toggle `BoardSyncConfig`.

Follow data must not contain Wallet credential payloads or Taiwan digital
identity assertions.
```

- [ ] **Step 2: Run full verification**

Run:

```bash
cd ansible_core/store
dart test
dart analyze
```

Expected: PASS.

Run:

```bash
cd ansible_core/ap
dart test
dart analyze
```

Expected: PASS.

Run:

```bash
cd ansible_core/domain
dart test
dart analyze
```

Expected: PASS.

Run:

```bash
cd ansible_sync/handlers
dart test
dart analyze
```

Expected: PASS.

Run:

```bash
cd ansible_node/app
flutter test
flutter analyze --no-fatal-infos
```

Expected: PASS.

- [ ] **Step 3: Check no identity data leaked into follow implementation**

Run:

```bash
rg -n "TrisAuraHumanityCredential|Verifiable Presentation|nationalId|legalName|birthDate|certificateSerial|MOICA|TW FidO" ansible_core ansible_sync ansible_node/app
```

Expected: matches only in wallet/VC files and docs, not in follow entities, follow repositories, follow AP payloads, follow services, or follow UI.

- [ ] **Step 4: Check generated artifacts and temporary files**

Run:

```bash
git status --short
```

Expected: only intentional source, generated Drift code, tests, and docs are changed. No `.dart_tool/test` files should be staged.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/protocol/ansible_sync_spec_v0.1.md docs/superpowers/specs/2026-05-04-follow-users-boards-design.md
git commit -m "docs: document follow implementation status"
```

---

## Self-Review Checklist

- Spec coverage: Tasks cover store state, repositories, AP protocol, domain transitions, remote board sync bridge, Following feed projection, Flutter controls, sync inbox routing, privacy boundary, and tests.
- Placeholder scan: This plan uses concrete file paths, commands, test names, expected failures, and implementation snippets.
- Type consistency: Entity names are `FollowTarget`, `FollowEdge`, `FollowActivityEvent`, and `OutboundFollowActivity`; repository names are `FollowRepository` and `FollowActivityOutboxRepository`; app labels match the design spec.
- Verification: Each package has a local test/analyze command, and the final task includes full workspace verification.
