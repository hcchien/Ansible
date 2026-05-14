# Messenger Contact Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users start encrypted messenger conversations by choosing human-readable contacts instead of typing raw DIDs.

**Architecture:** The app owns a local contact store that maps DID to handle, display name, local alias, relationship, trust state, and cached messenger availability. The relay exposes a non-consuming messenger device availability endpoint, while initial sends still reserve one-time pre-keys through the existing consuming pre-key bundle endpoint. Flutter resolvers combine local contact metadata, handle/DID resolution, and messenger availability for inbox, thread, profile, and contact picker UI.

**Tech Stack:** Dart, Flutter, Drift, Elixir/Phoenix Plug router, Ecto/Postgres, existing messenger relay APIs, `flutter test`, `dart test`, `mix test`.

---

## Source Documents

Read these first:

- `docs/superpowers/specs/2026-05-14-messenger-contact-discovery-design.md`
- `docs/superpowers/specs/2026-05-14-encrypted-messenger-protocol-design.md`
- `docs/superpowers/plans/2026-05-14-encrypted-messenger-protocol.md`
- `ansible_core/store/lib/src/db/app_database.dart`
- `ansible_core/store/lib/src/repositories/messenger_repository.dart`
- `ansible_node/app/lib/screens/inbox_screen.dart`
- `ansible_node/app/lib/screens/messenger_thread_screen.dart`
- `ansible_node/app/lib/services/messenger_sync_service.dart`
- `ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`

## File Structure

Create local contact store:

- Create `ansible_core/store/lib/src/schema/contact_records.dart`
- Create `ansible_core/store/lib/src/entities/contact_entities.dart`
- Create `ansible_core/store/lib/src/repositories/contact_repository.dart`
- Create `ansible_core/store/lib/src/repositories/drift/drift_contact_repository.dart`
- Modify `ansible_core/store/lib/src/db/app_database.dart`
- Modify `ansible_core/store/lib/ansible_store.dart`
- Test `ansible_core/store/test/contact_repository_test.dart`

Create relay non-consuming messenger availability endpoint:

- Modify `ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/controllers/messenger_controller.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Test `ansible_relay/phoenix/test/messenger_controller_test.exs`

Create app contact and availability resolvers:

- Create `ansible_node/app/lib/services/contact_resolver.dart`
- Create `ansible_node/app/lib/services/messenger_contact_resolver.dart`
- Modify `ansible_node/app/lib/services/messenger_relay_client.dart`
- Test `ansible_node/app/test/contact_resolver_test.dart`
- Test `ansible_node/app/test/messenger_contact_resolver_test.dart`

Create contact picker and wire messenger UI labels:

- Create `ansible_node/app/lib/screens/contact_picker_screen.dart`
- Modify `ansible_node/app/lib/screens/inbox_screen.dart`
- Modify `ansible_node/app/lib/screens/messenger_thread_screen.dart`
- Modify `ansible_node/app/lib/l10n/subpage_l10n.dart`
- Test `ansible_node/app/test/contact_picker_screen_test.dart`
- Test `ansible_node/app/test/inbox_screen_test.dart`
- Test `ansible_node/app/test/messenger_thread_screen_test.dart`

## Data Model

Use these Dart enum names and string values consistently inside the app and
local Drift store. Relay/API DTOs convert snake_case JSON values at the
boundary; the contact database must not store relay snake_case strings.

```dart
enum ContactRelationship {
  following,
  follower,
  mutual,
  conversation,
  boardPeer,
  invite,
  manual,
  unknown,
  blocked,
}

enum ContactTrustState {
  known,
  changed,
  unverified,
  blocked,
}

enum MessengerAvailability {
  available,
  noDevices,
  noPreKeys,
  blocked,
  unresolved,
  relayUnavailable,
}
```

The contact entity must expose:

```dart
class ContactRecord {
  final String subjectDid;
  final String? handle;
  final String? displayName;
  final String? localAlias;
  final String? avatarUrl;
  final ContactRelationship relationship;
  final String source;
  final ContactTrustState trustState;
  final MessengerAvailability messengerAvailability;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastResolvedAt;

  const ContactRecord({
    required this.subjectDid,
    this.handle,
    this.displayName,
    this.localAlias,
    this.avatarUrl,
    this.relationship = ContactRelationship.unknown,
    this.source = 'unknown',
    this.trustState = ContactTrustState.unverified,
    this.messengerAvailability = MessengerAvailability.unresolved,
    required this.createdAt,
    required this.updatedAt,
    this.lastResolvedAt,
  });

  String get label {
    final alias = localAlias?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final resolvedHandle = handle?.trim();
    if (resolvedHandle != null && resolvedHandle.isNotEmpty) return resolvedHandle;
    return shortDid;
  }

  String get shortDid {
    if (subjectDid.length <= 18) return subjectDid;
    return '${subjectDid.substring(0, 10)}…${subjectDid.substring(subjectDid.length - 6)}';
  }
}
```

## Task 1: Contact Store

**Files:**

- Create `ansible_core/store/lib/src/schema/contact_records.dart`
- Create `ansible_core/store/lib/src/entities/contact_entities.dart`
- Create `ansible_core/store/lib/src/repositories/contact_repository.dart`
- Create `ansible_core/store/lib/src/repositories/drift/drift_contact_repository.dart`
- Modify `ansible_core/store/lib/src/db/app_database.dart`
- Modify `ansible_core/store/lib/ansible_store.dart`
- Test `ansible_core/store/test/contact_repository_test.dart`

- [ ] **Step 1: Write failing repository test**

Create `ansible_core/store/test/contact_repository_test.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('stores contacts and prefers local alias for labels', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftContactRepository(db);

    final now = DateTime.utc(2026, 5, 14);
    await repo.upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:alice123456789',
        handle: 'alice.elix.app',
        displayName: 'Alice',
        localAlias: '設計夥伴 Alice',
        relationship: ContactRelationship.manual,
        source: 'manual',
        trustState: ContactTrustState.known,
        createdAt: now,
        updatedAt: now,
        lastResolvedAt: now,
      ),
    );

    final contact = await repo.contactForDid('did:plc:alice123456789');
    expect(contact!.label, '設計夥伴 Alice');
    expect(contact.handle, 'alice.elix.app');

    final contacts = await repo.listContacts();
    expect(contacts.single.subjectDid, 'did:plc:alice123456789');
  });

  test('detects handle identity changes without overwriting DID silently', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftContactRepository(db);
    final now = DateTime.utc(2026, 5, 14);

    await repo.upsertContact(
      ContactRecord(
        subjectDid: 'did:plc:old',
        handle: 'alice.elix.app',
        trustState: ContactTrustState.known,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final result = await repo.recordHandleResolution(
      handle: 'alice.elix.app',
      resolvedDid: 'did:plc:new',
      resolvedAt: now.add(const Duration(minutes: 1)),
    );

    expect(result.trustState, ContactTrustState.changed);
    expect((await repo.contactForDid('did:plc:old'))!.trustState, ContactTrustState.changed);
    expect(await repo.contactForDid('did:plc:new'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_core/store
dart test test/contact_repository_test.dart
```

Expected: FAIL because `ContactRecord`, `ContactRelationship`, and
`DriftContactRepository` do not exist.

- [ ] **Step 3: Add contact entity and repository interface**

Create `ansible_core/store/lib/src/entities/contact_entities.dart` with the
enums and `ContactRecord` class from the Data Model section.

Create `ansible_core/store/lib/src/repositories/contact_repository.dart`:

```dart
import '../entities/contact_entities.dart';

abstract class ContactRepository {
  Future<void> upsertContact(ContactRecord contact);
  Future<ContactRecord?> contactForDid(String subjectDid);
  Future<ContactRecord?> contactForHandle(String handle);
  Future<List<ContactRecord>> listContacts();

  Future<ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  });
}
```

- [ ] **Step 4: Add Drift schema and database export**

Create `ansible_core/store/lib/src/schema/contact_records.dart`:

```dart
import 'package:drift/drift.dart';

class ContactRecords extends Table {
  TextColumn get subjectDid => text()();
  TextColumn get handle => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get localAlias => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get relationship => text().withDefault(const Constant('unknown'))();
  TextColumn get source => text().withDefault(const Constant('unknown'))();
  TextColumn get trustState => text().withDefault(const Constant('unverified'))();
  TextColumn get messengerAvailability => text().withDefault(const Constant('unresolved'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastResolvedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {subjectDid};
}
```

Modify `ansible_core/store/lib/src/db/app_database.dart`:

- Import `../schema/contact_records.dart`.
- Add `ContactRecords` to the `@DriftDatabase(tables: [...])` table list.
- Increment schema version by one.

Modify `ansible_core/store/lib/ansible_store.dart` to export:

```dart
export 'src/entities/contact_entities.dart';
export 'src/repositories/contact_repository.dart';
export 'src/repositories/drift/drift_contact_repository.dart';
```

- [ ] **Step 5: Implement DriftContactRepository**

Create `ansible_core/store/lib/src/repositories/drift/drift_contact_repository.dart`:

```dart
import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/contact_entities.dart' as entity;
import '../contact_repository.dart';

class DriftContactRepository implements ContactRepository {
  DriftContactRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> upsertContact(entity.ContactRecord contact) {
    return _db.into(_db.contactRecords).insertOnConflictUpdate(
      ContactRecordsCompanion.insert(
        subjectDid: contact.subjectDid,
        handle: Value(contact.handle),
        displayName: Value(contact.displayName),
        localAlias: Value(contact.localAlias),
        avatarUrl: Value(contact.avatarUrl),
        relationship: Value(contact.relationship.name),
        source: Value(contact.source),
        trustState: Value(contact.trustState.name),
        messengerAvailability: Value(contact.messengerAvailability.name),
        createdAt: contact.createdAt,
        updatedAt: contact.updatedAt,
        lastResolvedAt: Value(contact.lastResolvedAt),
      ),
    );
  }

  @override
  Future<entity.ContactRecord?> contactForDid(String subjectDid) async {
    final row = await (_db.select(_db.contactRecords)
          ..where((table) => table.subjectDid.equals(subjectDid)))
        .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<entity.ContactRecord?> contactForHandle(String handle) async {
    final row = await (_db.select(_db.contactRecords)
          ..where((table) => table.handle.equals(handle)))
        .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<List<entity.ContactRecord>> listContacts() async {
    final rows = await (_db.select(_db.contactRecords)
          ..orderBy([(table) => OrderingTerm.asc(table.handle)]))
        .get();
    return rows.map(_map).toList(growable: false);
  }

  @override
  Future<entity.ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  }) async {
    final existing = await contactForHandle(handle);
    if (existing == null) {
      final contact = entity.ContactRecord(
        subjectDid: resolvedDid,
        handle: handle,
        trustState: entity.ContactTrustState.known,
        createdAt: resolvedAt,
        updatedAt: resolvedAt,
        lastResolvedAt: resolvedAt,
      );
      await upsertContact(contact);
      return contact;
    }
    if (existing.subjectDid != resolvedDid) {
      final changed = existing.copyWith(
        trustState: entity.ContactTrustState.changed,
        updatedAt: resolvedAt,
        lastResolvedAt: resolvedAt,
      );
      await upsertContact(changed);
      return changed;
    }
    final refreshed = existing.copyWith(
      trustState: entity.ContactTrustState.known,
      updatedAt: resolvedAt,
      lastResolvedAt: resolvedAt,
    );
    await upsertContact(refreshed);
    return refreshed;
  }

  entity.ContactRecord _map(ContactRecord row) {
    return entity.ContactRecord(
      subjectDid: row.subjectDid,
      handle: row.handle,
      displayName: row.displayName,
      localAlias: row.localAlias,
      avatarUrl: row.avatarUrl,
      relationship: entity.ContactRelationship.parse(row.relationship),
      source: row.source,
      trustState: entity.ContactTrustState.parse(row.trustState),
      messengerAvailability:
          entity.MessengerAvailability.parse(row.messengerAvailability),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastResolvedAt: row.lastResolvedAt,
    );
  }
}
```

Add `copyWith` and `parse` helpers to `ContactRecord` / enums in the entity file
so this repository compiles.

- [ ] **Step 6: Generate Drift code and run store tests**

Run:

```bash
cd ansible_core/store
dart run build_runner build --delete-conflicting-outputs
dart format lib test/contact_repository_test.dart
dart test test/contact_repository_test.dart
dart test
```

Expected: all store tests pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add ansible_core/store
git commit -m "Add local contact store"
```

## Task 2: Relay Messenger Device Availability Endpoint

**Files:**

- Modify `ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/controllers/messenger_controller.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Test `ansible_relay/phoenix/test/messenger_controller_test.exs`

- [ ] **Step 1: Add failing non-consuming availability test**

Append to `ansible_relay/phoenix/test/messenger_controller_test.exs`:

```elixir
test "device availability does not consume one-time pre-keys" do
  assert post_json("/api/v1/messenger/devices", %{
           "subject_did" => "did:plc:bob",
           "device_id" => "msgdev_bob",
           "bundle" => %{
             "messenger_identity_key" => "bob_identity_public",
             "signed_pre_key_id" => 42,
             "signed_pre_key" => "bob_signed_pre_key",
             "signed_pre_key_signature" => "bob_signed_pre_key_sig"
           },
           "binding" => %{"subject_did" => "did:plc:bob", "device_id" => "msgdev_bob"},
           "binding_signature" => "dev-signature"
         }).status == 201

  assert post_json("/api/v1/messenger/pre-keys", %{
           "subject_did" => "did:plc:bob",
           "device_id" => "msgdev_bob",
           "pre_keys" => [%{"pre_key_id" => 1001, "pre_key" => "bob_one_time_pre_key"}],
           "request_signature" => "dev-signature"
         }).status == 201

  availability = get_json("/api/v1/messenger/devices/did:plc:bob")
  assert availability.status == 200
  assert %{"devices" => [device]} = Jason.decode!(availability.resp_body)
  assert device["has_one_time_pre_keys"] == true
  refute Map.has_key?(device, "one_time_pre_key")
  refute Map.has_key?(device, "one_time_pre_key_id")

  consuming_bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:bob")
  assert %{"devices" => [reserved_device]} = Jason.decode!(consuming_bundle.resp_body)
  assert reserved_device["one_time_pre_key_id"] == 1001
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_relay/phoenix
mix test test/messenger_controller_test.exs
```

Expected: FAIL with 404 for `GET /api/v1/messenger/devices/:subject_did`.

- [ ] **Step 3: Implement `MessengerStore.device_availability/1`**

Add to `AnsibleRelay.MessengerStore`:

```elixir
def device_availability(subject_did) do
  devices =
    Device
    |> where([device], device.subject_did == ^subject_did)
    |> order_by([device], asc: device.device_id)
    |> Repo.all()
    |> Enum.map(fn device ->
      device
      |> device_map()
      |> Map.put("has_one_time_pre_keys", has_available_pre_keys?(device.subject_did, device.device_id))
    end)

  {:ok, %{subject_did: subject_did, devices: devices}}
end

defp has_available_pre_keys?(subject_did, device_id) do
  Repo.exists?(
    from pre_key in PreKey,
      where:
        pre_key.subject_did == ^subject_did and
          pre_key.device_id == ^device_id and
          is_nil(pre_key.reserved_at)
  )
end
```

- [ ] **Step 4: Wire controller and route**

Add to `MessengerController`:

```elixir
def devices(conn, %{"subject_did" => subject_did}) do
  case MessengerStore.device_availability(subject_did) do
    {:ok, body} -> send_json(conn, 200, body)
    {:error, reason} -> send_json(conn, 422, %{error: to_string(reason)})
  end
end
```

Add to `Router` before the consuming pre-key bundle route:

```elixir
get "/api/v1/messenger/devices/:subject_did" do
  AnsibleRelay.Web.Controllers.MessengerController.devices(conn, %{
    "subject_did" => subject_did
  })
end
```

- [ ] **Step 5: Run relay tests**

Run:

```bash
cd ansible_relay/phoenix
mix format lib/ansible_relay/messenger_store.ex lib/ansible_relay/web/controllers/messenger_controller.ex lib/ansible_relay/web/router.ex test/messenger_controller_test.exs
mix test test/messenger_controller_test.exs
mix test
```

Expected: all relay tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex ansible_relay/phoenix/lib/ansible_relay/web/controllers/messenger_controller.ex ansible_relay/phoenix/lib/ansible_relay/web/router.ex ansible_relay/phoenix/test/messenger_controller_test.exs
git commit -m "Add messenger device availability endpoint"
```

## Task 3: App Contact And Messenger Availability Resolvers

**Files:**

- Create `ansible_node/app/lib/services/contact_resolver.dart`
- Create `ansible_node/app/lib/services/messenger_contact_resolver.dart`
- Modify `ansible_node/app/lib/services/messenger_relay_client.dart`
- Test `ansible_node/app/test/contact_resolver_test.dart`
- Test `ansible_node/app/test/messenger_contact_resolver_test.dart`

- [ ] **Step 1: Add failing ContactResolver tests**

Create `ansible_node/app/test/contact_resolver_test.dart`:

```dart
import 'package:ansible_node/services/contact_resolver.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves DID input into a local contact record', () async {
    final repo = _FakeContactRepository();
    final resolver = ContactResolver(repository: repo, now: () => DateTime.utc(2026, 5, 14));

    final result = await resolver.resolveInput('did:plc:alice');

    expect(result.subjectDid, 'did:plc:alice');
    expect(result.label, startsWith('did:plc'));
    expect((await repo.contactForDid('did:plc:alice'))!.subjectDid, 'did:plc:alice');
  });

  test('detects handle identity changes through repository result', () async {
    final repo = _FakeContactRepository();
    final resolver = ContactResolver(
      repository: repo,
      handleResolver: (handle) async => 'did:plc:new',
      now: () => DateTime.utc(2026, 5, 14),
    );
    await repo.upsertContact(ContactRecord(
      subjectDid: 'did:plc:old',
      handle: 'alice.elix.app',
      trustState: ContactTrustState.known,
      createdAt: DateTime.utc(2026, 5, 14),
      updatedAt: DateTime.utc(2026, 5, 14),
    ));

    final result = await resolver.resolveInput('alice.elix.app');

    expect(result.subjectDid, 'did:plc:old');
    expect(result.trustState, ContactTrustState.changed);
  });
}
```

Use a small fake `ContactRepository` in the test. It should implement the same
handle-change behavior as Task 1.

- [ ] **Step 2: Add failing MessengerContactResolver tests**

Create `ansible_node/app/test/messenger_contact_resolver_test.dart`:

```dart
import 'package:ansible_node/services/messenger_contact_resolver.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks contact available when relay reports device with one-time pre-key', () async {
    final relay = _FakeMessengerRelayClient(
      response: const MessengerDeviceAvailabilityResponse(
        subjectDid: 'did:plc:alice',
        devices: [
          MessengerDeviceAvailability(
            deviceId: 'msgdev_alice',
            messengerIdentityKey: 'alice_identity',
            signedPreKeyId: 1,
            signedPreKey: 'alice_signed',
            signedPreKeySignature: 'alice_sig',
            hasOneTimePreKeys: true,
          ),
        ],
      ),
    );
    final resolver = MessengerContactResolver(relayClient: relay);

    final availability = await resolver.resolveAvailability(
      ContactRecord(
        subjectDid: 'did:plc:alice',
        createdAt: DateTime.utc(2026, 5, 14),
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    );

    expect(availability, MessengerAvailability.available);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
cd ansible_node/app
flutter test test/contact_resolver_test.dart test/messenger_contact_resolver_test.dart
```

Expected: FAIL because resolver classes and relay DTOs do not exist.

- [ ] **Step 4: Extend MessengerRelayClient with availability DTO**

Add DTOs to `messenger_relay_client.dart`:

```dart
class MessengerDeviceAvailabilityResponse {
  final String subjectDid;
  final List<MessengerDeviceAvailability> devices;

  const MessengerDeviceAvailabilityResponse({
    required this.subjectDid,
    required this.devices,
  });

  factory MessengerDeviceAvailabilityResponse.fromJson(Map<String, dynamic> json) {
    final devices = json['devices'];
    return MessengerDeviceAvailabilityResponse(
      subjectDid: json['subject_did'] as String,
      devices: devices is List
          ? devices
              .whereType<Map>()
              .map((device) => MessengerDeviceAvailability.fromJson(Map<String, dynamic>.from(device)))
              .toList(growable: false)
          : const [],
    );
  }
}

class MessengerDeviceAvailability {
  final String deviceId;
  final String messengerIdentityKey;
  final int signedPreKeyId;
  final String signedPreKey;
  final String signedPreKeySignature;
  final bool hasOneTimePreKeys;

  const MessengerDeviceAvailability({
    required this.deviceId,
    required this.messengerIdentityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    required this.hasOneTimePreKeys,
  });

  factory MessengerDeviceAvailability.fromJson(Map<String, dynamic> json) {
    return MessengerDeviceAvailability(
      deviceId: json['device_id'] as String,
      messengerIdentityKey: json['messenger_identity_key'] as String,
      signedPreKeyId: json['signed_pre_key_id'] as int,
      signedPreKey: json['signed_pre_key'] as String,
      signedPreKeySignature: json['signed_pre_key_signature'] as String,
      hasOneTimePreKeys: json['has_one_time_pre_keys'] == true,
    );
  }
}
```

Add method:

```dart
Future<MessengerDeviceAvailabilityResponse> fetchDeviceAvailability(String subjectDid) async {
  final body = await _getJson(
    '/api/v1/messenger/devices/${Uri.encodeComponent(subjectDid)}',
  );
  return MessengerDeviceAvailabilityResponse.fromJson(body);
}
```

- [ ] **Step 5: Implement ContactResolver and MessengerContactResolver**

Create `contact_resolver.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';

typedef HandleResolver = Future<String> Function(String handle);

class ContactResolver {
  ContactResolver({
    required this.repository,
    this.handleResolver,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  final ContactRepository repository;
  final HandleResolver? handleResolver;
  final DateTime Function() now;

  Future<ContactRecord> resolveInput(String input) async {
    final normalized = input.trim();
    if (normalized.startsWith('did:')) {
      final existing = await repository.contactForDid(normalized);
      if (existing != null) return existing;
      final timestamp = now();
      final contact = ContactRecord(
        subjectDid: normalized,
        source: 'manual',
        trustState: ContactTrustState.unverified,
        createdAt: timestamp,
        updatedAt: timestamp,
        lastResolvedAt: timestamp,
      );
      await repository.upsertContact(contact);
      return contact;
    }

    final resolve = handleResolver;
    if (resolve == null) {
      throw StateError('handle_resolver_unavailable');
    }
    final resolvedDid = await resolve(normalized);
    return repository.recordHandleResolution(
      handle: normalized,
      resolvedDid: resolvedDid,
      resolvedAt: now(),
    );
  }
}
```

Create `messenger_contact_resolver.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';

import 'messenger_relay_client.dart';

class MessengerContactResolver {
  MessengerContactResolver({required this.relayClient});

  final MessengerRelayClient relayClient;

  Future<MessengerAvailability> resolveAvailability(ContactRecord contact) async {
    if (contact.relationship == ContactRelationship.blocked ||
        contact.trustState == ContactTrustState.blocked) {
      return MessengerAvailability.blocked;
    }
    if (contact.trustState == ContactTrustState.changed) {
      return MessengerAvailability.unresolved;
    }
    try {
      final response = await relayClient.fetchDeviceAvailability(contact.subjectDid);
      if (response.devices.isEmpty) return MessengerAvailability.noDevices;
      if (response.devices.any((device) => device.hasOneTimePreKeys)) {
        return MessengerAvailability.available;
      }
      return MessengerAvailability.noPreKeys;
    } catch (_) {
      return MessengerAvailability.relayUnavailable;
    }
  }
}
```

- [ ] **Step 6: Run app resolver tests**

Run:

```bash
cd ansible_node/app
dart format lib/services/contact_resolver.dart lib/services/messenger_contact_resolver.dart lib/services/messenger_relay_client.dart test/contact_resolver_test.dart test/messenger_contact_resolver_test.dart
flutter test test/contact_resolver_test.dart test/messenger_contact_resolver_test.dart test/messenger_relay_client_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add ansible_node/app/lib/services/contact_resolver.dart ansible_node/app/lib/services/messenger_contact_resolver.dart ansible_node/app/lib/services/messenger_relay_client.dart ansible_node/app/test/contact_resolver_test.dart ansible_node/app/test/messenger_contact_resolver_test.dart ansible_node/app/test/messenger_relay_client_test.dart
git commit -m "Add contact and messenger availability resolvers"
```

## Task 4: Contact Picker And Messenger UI Labels

**Files:**

- Create `ansible_node/app/lib/screens/contact_picker_screen.dart`
- Modify `ansible_node/app/lib/screens/inbox_screen.dart`
- Modify `ansible_node/app/lib/screens/messenger_thread_screen.dart`
- Modify `ansible_node/app/lib/l10n/subpage_l10n.dart`
- Test `ansible_node/app/test/contact_picker_screen_test.dart`
- Test `ansible_node/app/test/inbox_screen_test.dart`
- Test `ansible_node/app/test/messenger_thread_screen_test.dart`

- [ ] **Step 1: Add failing contact picker widget test**

Create `ansible_node/app/test/contact_picker_screen_test.dart`:

```dart
import 'package:ansible_node/screens/contact_picker_screen.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('contact picker returns selected contact DID', (tester) async {
    final contacts = [
      ContactRecord(
        subjectDid: 'did:plc:alice',
        handle: 'alice.elix.app',
        displayName: 'Alice',
        messengerAvailability: MessengerAvailability.available,
        createdAt: DateTime.utc(2026, 5, 14),
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    ];

    String? selectedDid;
    await tester.pumpWidget(
      MaterialApp(
        home: ContactPickerScreen(
          contacts: contacts,
          onContactSelected: (contact) => selectedDid = contact.subjectDid,
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice.elix.app'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    expect(selectedDid, 'did:plc:alice');
  });
}
```

- [ ] **Step 2: Add failing UI label tests**

Extend `inbox_screen_test.dart` so a repository contact for `did:plc:bob` causes
the inbox row to show `Bob` instead of raw DID.

Extend `messenger_thread_screen_test.dart` so `MessengerThreadScreen` accepts an
optional `contact` and renders `Bob` in the header with `bob.elix.app` subtitle.

- [ ] **Step 3: Run widget tests to verify failure**

Run:

```bash
cd ansible_node/app
flutter test test/contact_picker_screen_test.dart test/inbox_screen_test.dart test/messenger_thread_screen_test.dart
```

Expected: FAIL because `ContactPickerScreen` and contact-aware labels do not
exist.

- [ ] **Step 4: Implement ContactPickerScreen**

Create `contact_picker_screen.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class ContactPickerScreen extends StatelessWidget {
  const ContactPickerScreen({
    super.key,
    required this.contacts,
    required this.onContactSelected,
  });

  final List<ContactRecord> contacts;
  final ValueChanged<ContactRecord> onContactSelected;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: 'CONTACTS',
      leadingLabel: text.t('backWorkspace'),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        itemCount: contacts.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AnsibleDesign.ruleSoft),
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(contact.label),
            subtitle: Text(contact.handle ?? contact.shortDid),
            trailing: Text(_availabilityLabel(contact.messengerAvailability)),
            enabled: contact.messengerAvailability == MessengerAvailability.available,
            onTap: contact.messengerAvailability == MessengerAvailability.available
                ? () => onContactSelected(contact)
                : null,
          );
        },
      ),
    );
  }

  String _availabilityLabel(MessengerAvailability availability) {
    return switch (availability) {
      MessengerAvailability.available => '可私訊',
      MessengerAvailability.noDevices => '未啟用',
      MessengerAvailability.noPreKeys => '暫不可用',
      MessengerAvailability.blocked => '已封鎖',
      MessengerAvailability.unresolved => '未確認',
      MessengerAvailability.relayUnavailable => '稍後再試',
    };
  }
}
```

- [ ] **Step 5: Wire labels into Inbox and Thread**

Modify `InboxScreen` to accept optional `ContactRepository contactRepository`.
When rendering each conversation, load `contactRepository.contactForDid(peerDid)`
and use `contact.label` as row title when present.

Modify `MessengerThreadScreen` constructor:

```dart
const MessengerThreadScreen({
  super.key,
  required this.conversationId,
  required this.messengerService,
  this.senderDid = 'did:plc:local',
  this.contact,
});

final ContactRecord? contact;
```

Header title should be `contact?.label ?? conversationId`. Header subtitle
should be `contact?.handle ?? contact?.shortDid`.

- [ ] **Step 6: Add i18n strings**

Modify `subpage_l10n.dart` English and Chinese maps:

```dart
'contactsTitle': 'Contacts',
'contactAvailable': '可私訊',
'contactNoDevices': '未啟用',
'contactNoPreKeys': '暫不可用',
'contactBlocked': '已封鎖',
'contactUnresolved': '未確認',
'contactRelayUnavailable': '稍後再試',
```

Use English values in the English map:

```dart
'contactsTitle': 'Contacts',
'contactAvailable': 'Message',
'contactNoDevices': 'Not enabled',
'contactNoPreKeys': 'Unavailable',
'contactBlocked': 'Blocked',
'contactUnresolved': 'Unverified',
'contactRelayUnavailable': 'Try later',
```

- [ ] **Step 7: Run widget and i18n tests**

Run:

```bash
cd ansible_node/app
dart format lib/screens/contact_picker_screen.dart lib/screens/inbox_screen.dart lib/screens/messenger_thread_screen.dart lib/l10n/subpage_l10n.dart test/contact_picker_screen_test.dart test/inbox_screen_test.dart test/messenger_thread_screen_test.dart
flutter test test/contact_picker_screen_test.dart test/inbox_screen_test.dart test/messenger_thread_screen_test.dart test/app_i18n_coverage_test.dart
```

Expected: all tests pass.

- [ ] **Step 8: Commit Task 4**

```bash
git add ansible_node/app/lib/screens/contact_picker_screen.dart ansible_node/app/lib/screens/inbox_screen.dart ansible_node/app/lib/screens/messenger_thread_screen.dart ansible_node/app/lib/l10n/subpage_l10n.dart ansible_node/app/test/contact_picker_screen_test.dart ansible_node/app/test/inbox_screen_test.dart ansible_node/app/test/messenger_thread_screen_test.dart
git commit -m "Add messenger contact picker UI"
```

## Task 5: Full Verification

**Files:**

- No new production files unless tests reveal integration failures.

- [ ] **Step 1: Run relay verification**

Run:

```bash
cd ansible_relay/phoenix
mix test
```

Expected: all tests pass.

- [ ] **Step 2: Run store verification**

Run:

```bash
cd ansible_core/store
dart test
```

Expected: all tests pass.

- [ ] **Step 3: Run app verification**

Run:

```bash
cd ansible_node/app
flutter analyze
flutter test
```

Expected: no analyzer issues and all tests pass.

- [ ] **Step 4: Commit verification fixes if needed**

If any verification fix was required:

```bash
git add <changed-files>
git commit -m "Stabilize messenger contact discovery"
```

If no fixes were required, do not create an empty commit.

## Self-Review

- Spec coverage: The plan covers local contact mapping, handle identity change
  detection, non-consuming relay availability, app availability resolver, contact
  picker UI, inbox/thread labels, and full verification.
- Placeholder scan: No task uses placeholder-only instructions; every task names
  files, commands, and expected outcomes.
- Type consistency: `ContactRecord`, `ContactRelationship`,
  `ContactTrustState`, and `MessengerAvailability` are defined once and reused
  across store, app services, and UI tasks.
