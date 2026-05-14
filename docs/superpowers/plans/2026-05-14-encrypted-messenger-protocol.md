# Encrypted Messenger Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first 1:1 encrypted text messenger path using app-held Signal-style crypto state, Rust API boundaries, Flutter local storage, and opaque relay mailbox APIs.

**Architecture:** The app owns messenger private keys, session state, plaintext, and decrypt/encrypt orchestration. The Rust layer exposes a messenger crypto facade so Dart never handles raw protocol internals. The Elixir/Phoenix relay stores DID-signed public device bundles, consumes one-time pre-keys, and transports opaque ciphertext without plaintext access.

**Tech Stack:** Rust, Flutter Rust Bridge, Dart, Flutter, Drift, Elixir/Phoenix Plug router, Jason, GenServer dev stores, `cargo test`, `flutter test`, `dart test`, `mix test`.

---

## Source Documents

Read these first:

- `docs/superpowers/specs/2026-05-14-encrypted-messenger-protocol-design.md`
- `docs/superpowers/specs/2026-05-11-app-mediated-web-session-design.md`
- `docs/superpowers/specs/2026-05-11-web-development-design.md`
- `ansible_rust_core/src/api.rs`
- `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- `ansible_core/store/lib/src/db/app_database.dart`
- `ansible_node/app/lib/screens/inbox_screen.dart`

## File Structure

Create Rust messenger crypto boundary:

- `ansible_rust_core/src/messenger.rs`
- `ansible_rust_core/src/api_messenger.rs`
- Modify `ansible_rust_core/src/lib.rs`
- Modify `ansible_rust_core/Cargo.toml`
- Test `ansible_rust_core/tests/messenger_crypto_test.rs`

Create relay messenger modules:

- `ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/messenger_controller.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/application.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Test `ansible_relay/phoenix/test/messenger_controller_test.exs`

Create app store and repositories:

- `ansible_core/store/lib/src/schema/messenger_devices.dart`
- `ansible_core/store/lib/src/schema/messenger_pre_keys.dart`
- `ansible_core/store/lib/src/schema/messenger_sessions.dart`
- `ansible_core/store/lib/src/schema/messenger_conversations.dart`
- `ansible_core/store/lib/src/schema/messenger_messages.dart`
- `ansible_core/store/lib/src/schema/messenger_mailbox_cursors.dart`
- `ansible_core/store/lib/src/entities/messenger_entities.dart`
- `ansible_core/store/lib/src/repositories/messenger_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_messenger_repository.dart`
- Modify `ansible_core/store/lib/src/db/app_database.dart`
- Modify `ansible_core/store/lib/ansible_store.dart`
- Test `ansible_core/store/test/messenger_repository_test.dart`

Create app messenger services:

- `ansible_node/app/lib/services/messenger_relay_client.dart`
- `ansible_node/app/lib/services/messenger_device_service.dart`
- `ansible_node/app/lib/services/messenger_sync_service.dart`
- `ansible_node/app/lib/services/messenger_crypto_bridge.dart`
- Test `ansible_node/app/test/messenger_relay_client_test.dart`
- Test `ansible_node/app/test/messenger_device_service_test.dart`
- Test `ansible_node/app/test/messenger_sync_service_test.dart`

Create app UI shell:

- Modify `ansible_node/app/lib/screens/inbox_screen.dart`
- Create `ansible_node/app/lib/screens/messenger_thread_screen.dart`
- Test `ansible_node/app/test/inbox_screen_test.dart`
- Test `ansible_node/app/test/messenger_thread_screen_test.dart`

## Dependency Decision

The first implementation task is a crypto dependency spike. The target is an
actual Signal-compatible Rust implementation behind `ansible_rust_core`.

The spike passes only when:

- It builds on the current host with `cargo test`.
- The chosen dependency can produce two devices, an initial ciphertext, and a
  successful decrypt in a Rust test.
- The API can serialize session state as bytes or a stable string for Dart
  persistence.

If official `signalapp/libsignal` cannot be integrated cleanly because of
unsupported external APIs or target build friction, use a maintained Rust
Signal-protocol implementation for MVP and keep the app-facing facade unchanged.

## Task 1: Rust Messenger Crypto Facade

**Files:**

- Create `ansible_rust_core/src/messenger.rs`
- Create `ansible_rust_core/src/api_messenger.rs`
- Modify `ansible_rust_core/src/lib.rs`
- Modify `ansible_rust_core/Cargo.toml`
- Test `ansible_rust_core/tests/messenger_crypto_test.rs`

- [ ] **Step 1: Add failing Rust crypto round-trip test**

Create `ansible_rust_core/tests/messenger_crypto_test.rs`:

```rust
use ansible_rust_core::messenger::{
    create_messenger_device, decrypt_inbound_message, encrypt_initial_message,
    generate_one_time_pre_keys, MessengerEncryptInput,
};

#[test]
fn messenger_crypto_round_trip_encrypts_for_remote_device() {
    let alice = create_messenger_device("did:plc:alice".to_string()).unwrap();
    let mut bob = create_messenger_device("did:plc:bob".to_string()).unwrap();
    let bob_pre_keys = generate_one_time_pre_keys(&mut bob, 1).unwrap();
    let bob_bundle = bob.public_bundle(bob_pre_keys[0].clone());

    let ciphertext = encrypt_initial_message(MessengerEncryptInput {
        local_device: alice.clone(),
        remote_bundle: bob_bundle,
        plaintext: b"hello bob".to_vec(),
    })
    .unwrap();

    assert_ne!(ciphertext.ciphertext, b"hello bob".to_vec());
    assert_eq!(ciphertext.protocol_version, "signal-mvp-v1");

    let plaintext = decrypt_inbound_message(&mut bob, ciphertext).unwrap();
    assert_eq!(plaintext.body, b"hello bob".to_vec());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cargo test -p ansible_rust_core --test messenger_crypto_test
```

Expected: fail because `ansible_rust_core::messenger` does not exist.

- [ ] **Step 3: Implement the messenger facade using the selected Signal-compatible dependency**

Add module exports to `ansible_rust_core/src/lib.rs`:

```rust
pub mod api;
pub mod api_atproto;
pub mod api_crdt;
pub mod api_messenger;
pub mod api_zkp;
pub mod messenger;
```

Implement these public types in `ansible_rust_core/src/messenger.rs`:

```rust
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MessengerDevice {
    pub subject_did: String,
    pub device_id: String,
    pub identity_key_public: String,
    pub identity_key_private: String,
    pub signed_pre_key_id: u32,
    pub signed_pre_key_public: String,
    pub signed_pre_key_private: String,
    pub signed_pre_key_signature: String,
    pub session_state: Option<String>,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MessengerPreKey {
    pub pre_key_id: u32,
    pub public_key: String,
    pub private_key: String,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MessengerPreKeyBundle {
    pub subject_did: String,
    pub device_id: String,
    pub identity_key: String,
    pub signed_pre_key_id: u32,
    pub signed_pre_key: String,
    pub signed_pre_key_signature: String,
    pub one_time_pre_key_id: u32,
    pub one_time_pre_key: String,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MessengerEncryptInput {
    pub local_device: MessengerDevice,
    pub remote_bundle: MessengerPreKeyBundle,
    pub plaintext: Vec<u8>,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MessengerCiphertext {
    pub protocol_version: String,
    pub ciphertext_type: String,
    pub ciphertext: Vec<u8>,
    pub updated_session_state: String,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MessengerPlaintext {
    pub body: Vec<u8>,
    pub updated_session_state: String,
}
```

Implement:

```rust
pub fn create_messenger_device(subject_did: String) -> Result<MessengerDevice, String>;
pub fn generate_one_time_pre_keys(device: &mut MessengerDevice, count: u32) -> Result<Vec<MessengerPreKey>, String>;
pub fn encrypt_initial_message(input: MessengerEncryptInput) -> Result<MessengerCiphertext, String>;
pub fn decrypt_inbound_message(device: &mut MessengerDevice, ciphertext: MessengerCiphertext) -> Result<MessengerPlaintext, String>;
```

Implementation notes:

- The selected library must perform real Signal-style session setup and message encryption.
- Do not add XOR, base64-only, or plaintext passthrough test adapters.
- Keep private keys and session state serializable only for the local app boundary.
- Return `signal-mvp-v1` as `protocol_version`.

- [ ] **Step 4: Add Flutter Rust Bridge API wrappers**

Create `ansible_rust_core/src/api_messenger.rs`:

```rust
use flutter_rust_bridge::frb;

pub use crate::messenger::{
    MessengerCiphertext, MessengerDevice, MessengerEncryptInput, MessengerPlaintext,
    MessengerPreKey, MessengerPreKeyBundle,
};

#[frb(sync)]
pub fn api_messenger_create_device(subject_did: String) -> Result<MessengerDevice, String> {
    crate::messenger::create_messenger_device(subject_did)
}

#[frb(sync)]
pub fn api_messenger_generate_pre_keys(
    mut device: MessengerDevice,
    count: u32,
) -> Result<Vec<MessengerPreKey>, String> {
    crate::messenger::generate_one_time_pre_keys(&mut device, count)
}

pub fn api_messenger_encrypt_initial_message(
    input: MessengerEncryptInput,
) -> Result<MessengerCiphertext, String> {
    crate::messenger::encrypt_initial_message(input)
}

pub fn api_messenger_decrypt_inbound_message(
    mut local_device: MessengerDevice,
    ciphertext: MessengerCiphertext,
) -> Result<MessengerPlaintext, String> {
    crate::messenger::decrypt_inbound_message(&mut local_device, ciphertext)
}
```

- [ ] **Step 5: Run Rust tests**

Run:

```bash
cargo test -p ansible_rust_core --test messenger_crypto_test
cargo test -p ansible_rust_core
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add ansible_rust_core
git commit -m "Add messenger crypto facade"
```

## Task 2: Relay Messenger Store And API

**Files:**

- Create `ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex`
- Create `ansible_relay/phoenix/lib/ansible_relay/web/controllers/messenger_controller.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/application.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Test `ansible_relay/phoenix/test/messenger_controller_test.exs`

- [ ] **Step 1: Write failing relay controller tests**

Create `ansible_relay/phoenix/test/messenger_controller_test.exs`:

```elixir
defmodule AnsibleRelay.MessengerControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router

  @opts Router.init([])

  test "publishes bundle, consumes one pre-key, stores ciphertext, and acks delivery" do
    publish = post_json("/api/v1/messenger/devices", %{
      "subject_did" => "did:plc:bob",
      "device_id" => "msgdev_bob",
      "bundle" => %{
        "messenger_identity_key" => "bob_identity_public",
        "signed_pre_key_id" => 42,
        "signed_pre_key" => "bob_signed_pre_key",
        "signed_pre_key_signature" => "bob_signed_pre_key_sig",
        "expires_at" => "2026-06-13T00:00:00Z"
      },
      "binding" => %{"subject_did" => "did:plc:bob", "device_id" => "msgdev_bob"},
      "binding_signature" => "dev-signature"
    })

    assert publish.status == 201

    prekeys = post_json("/api/v1/messenger/pre-keys", %{
      "subject_did" => "did:plc:bob",
      "device_id" => "msgdev_bob",
      "pre_keys" => [%{"pre_key_id" => 1001, "pre_key" => "bob_one_time_pre_key"}],
      "request_signature" => "dev-signature"
    })

    assert prekeys.status == 201

    bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:bob")
    assert bundle.status == 200
    assert %{"devices" => [device]} = Jason.decode!(bundle.resp_body)
    assert device["one_time_pre_key_id"] == 1001

    second_bundle = get_json("/api/v1/messenger/pre-key-bundles/did:plc:bob")
    assert %{"devices" => [second_device]} = Jason.decode!(second_bundle.resp_body)
    refute Map.has_key?(second_device, "one_time_pre_key_id")

    send_result = post_json("/api/v1/messenger/messages", %{
      "message_id" => "msg_test",
      "sender_did" => "did:plc:alice",
      "sender_device_id" => "msgdev_alice",
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "ciphertext_type" => "pre_key_signal_message",
      "ciphertext" => "base64-ciphertext",
      "protocol_version" => "signal-mvp-v1",
      "created_at" => "2026-05-14T00:00:00Z",
      "request_signature" => "dev-signature"
    })

    assert send_result.status == 202
    refute send_result.resp_body =~ "hello"

    mailbox = get_json("/api/v1/messenger/messages?recipient_device_id=msgdev_bob")
    assert %{"messages" => [message]} = Jason.decode!(mailbox.resp_body)
    assert message["message_id"] == "msg_test"
    assert message["ciphertext"] == "base64-ciphertext"

    ack = post_json("/api/v1/messenger/messages/msg_test/ack", %{
      "recipient_did" => "did:plc:bob",
      "recipient_device_id" => "msgdev_bob",
      "request_signature" => "dev-signature"
    })

    assert ack.status == 200
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  defp get_json(path) do
    conn(:get, path)
    |> Router.call(@opts)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_relay/phoenix
mix test test/messenger_controller_test.exs
```

Expected: fail because messenger routes do not exist.

- [ ] **Step 3: Implement `MessengerStore`**

Create `ansible_relay/phoenix/lib/ansible_relay/messenger_store.ex` with a
GenServer API:

```elixir
defmodule AnsibleRelay.MessengerStore do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(_), do: {:ok, %{devices: %{}, pre_keys: %{}, messages: %{}, acks: MapSet.new()}}

  def publish_device(attrs), do: GenServer.call(__MODULE__, {:publish_device, attrs})
  def publish_pre_keys(attrs), do: GenServer.call(__MODULE__, {:publish_pre_keys, attrs})
  def reserve_bundle(subject_did), do: GenServer.call(__MODULE__, {:reserve_bundle, subject_did})
  def store_message(attrs), do: GenServer.call(__MODULE__, {:store_message, attrs})
  def mailbox(recipient_device_id), do: GenServer.call(__MODULE__, {:mailbox, recipient_device_id})
  def ack(message_id, recipient_device_id), do: GenServer.call(__MODULE__, {:ack, message_id, recipient_device_id})
end
```

Required behavior:

- Key devices by `{subject_did, device_id}`.
- Key one-time pre-keys by `{subject_did, device_id, pre_key_id}`.
- `reserve_bundle/1` returns each device plus at most one one-time pre-key and
  removes the returned one-time pre-key.
- `store_message/1` rejects missing `message_id`, missing recipients, plaintext
  field names such as `plaintext` or `body`, and duplicate message ids.
- `mailbox/1` returns messages for the recipient device that are not acked.

- [ ] **Step 4: Register the store**

Modify `ansible_relay/phoenix/lib/ansible_relay/application.ex`:

```elixir
children = [
  AnsibleRelay.IdentityCache,
  AnsibleRelay.WebSessionStore,
  AnsibleRelay.MessengerStore
]
```

Keep existing children and insert `MessengerStore` near other in-memory relay
stores.

- [ ] **Step 5: Add controller and routes**

Add routes to `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`:

```elixir
post "/api/v1/messenger/devices" do
  AnsibleRelay.Web.Controllers.MessengerController.publish_device(conn, conn.body_params)
end

post "/api/v1/messenger/pre-keys" do
  AnsibleRelay.Web.Controllers.MessengerController.publish_pre_keys(conn, conn.body_params)
end

get "/api/v1/messenger/pre-key-bundles/:subject_did" do
  AnsibleRelay.Web.Controllers.MessengerController.pre_key_bundle(conn, %{"subject_did" => subject_did})
end

post "/api/v1/messenger/messages" do
  AnsibleRelay.Web.Controllers.MessengerController.send_message(conn, conn.body_params)
end

get "/api/v1/messenger/messages" do
  AnsibleRelay.Web.Controllers.MessengerController.mailbox(conn, conn.query_params)
end

post "/api/v1/messenger/messages/:message_id/ack" do
  AnsibleRelay.Web.Controllers.MessengerController.ack(conn, Map.put(conn.body_params, "message_id", message_id))
end
```

Create `messenger_controller.ex` that delegates to `MessengerStore` and returns
JSON status codes:

- `201` for device and pre-key publish.
- `200` for bundle and mailbox lookup.
- `202` for accepted ciphertext.
- `200` for ack.
- `422` for invalid payload.

- [ ] **Step 6: Run relay tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/messenger_controller_test.exs
mix test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add ansible_relay/phoenix/lib/ansible_relay ansible_relay/phoenix/test/messenger_controller_test.exs
git commit -m "Add relay messenger mailbox APIs"
```

## Task 3: App Store Messenger Schema

**Files:**

- Create schema/repository files listed in File Structure.
- Modify `ansible_core/store/lib/src/db/app_database.dart`
- Modify `ansible_core/store/lib/ansible_store.dart`
- Test `ansible_core/store/test/messenger_repository_test.dart`

- [ ] **Step 1: Write failing Drift repository test**

Create `ansible_core/store/test/messenger_repository_test.dart`:

```dart
import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  test('stores devices, sessions, conversations, and messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftMessengerRepository(db);

    await repo.upsertLocalDevice(
      MessengerDeviceRecord(
        subjectDid: 'did:plc:alice',
        deviceId: 'msgdev_alice',
        identityKeyPublic: 'alice_identity_public',
        identityKeyPrivateRef: 'secure:msgdev_alice',
        createdAt: DateTime.utc(2026, 5, 14),
      ),
    );

    await repo.saveSession(
      MessengerSessionRecord(
        localDeviceId: 'msgdev_alice',
        remoteDid: 'did:plc:bob',
        remoteDeviceId: 'msgdev_bob',
        sessionState: 'serialized-session',
        updatedAt: DateTime.utc(2026, 5, 14),
      ),
    );

    await repo.saveMessage(
      MessengerMessageRecord(
        messageId: 'msg_test',
        conversationId: 'did:plc:bob',
        direction: MessengerMessageDirection.outbound,
        status: MessengerMessageStatus.sent,
        plaintext: 'hello bob',
        ciphertextType: 'pre_key_signal_message',
        createdAt: DateTime.utc(2026, 5, 14),
      ),
    );

    final messages = await repo.messagesForConversation('did:plc:bob');
    expect(messages.single.plaintext, 'hello bob');
    expect(messages.single.status, MessengerMessageStatus.sent);

    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_core/store
dart test test/messenger_repository_test.dart
```

Expected: fail because messenger repository and schema do not exist.

- [ ] **Step 3: Add Drift tables and migration**

Create tables:

- `messenger_devices`
- `messenger_pre_keys`
- `messenger_sessions`
- `messenger_conversations`
- `messenger_messages`
- `messenger_mailbox_cursors`

Modify `AppDatabase`:

- Import the new schema files.
- Add the new tables to `@DriftDatabase(tables: [...])`.
- Increment `schemaVersion` from `14` to `15`.
- In `onUpgrade`, add:

```dart
if (from < 15) {
  await _createTableIfMissing(m, messengerDevices);
  await _createTableIfMissing(m, messengerPreKeys);
  await _createTableIfMissing(m, messengerSessions);
  await _createTableIfMissing(m, messengerConversations);
  await _createTableIfMissing(m, messengerMessages);
  await _createTableIfMissing(m, messengerMailboxCursors);
}
```

- [ ] **Step 4: Add entities and `DriftMessengerRepository`**

Create enum values:

```dart
enum MessengerMessageDirection { inbound, outbound }
enum MessengerMessageStatus { pending, sent, received, decryptFailed, acked }
```

Repository methods:

```dart
Future<void> upsertLocalDevice(MessengerDeviceRecord device);
Future<void> upsertRemoteDevice(MessengerDeviceRecord device);
Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys);
Future<void> markPreKeyPublished(String deviceId, int preKeyId);
Future<void> saveSession(MessengerSessionRecord session);
Future<MessengerSessionRecord?> sessionFor(String localDeviceId, String remoteDeviceId);
Future<void> saveMessage(MessengerMessageRecord message);
Future<List<MessengerMessageRecord>> messagesForConversation(String conversationId);
Future<void> saveMailboxCursor(String localDeviceId, String cursor);
```

- [ ] **Step 5: Regenerate Drift code**

Run:

```bash
cd ansible_core/store
dart run build_runner build --delete-conflicting-outputs
dart format lib test
dart test test/messenger_repository_test.dart
```

Expected: messenger repository test passes.

- [ ] **Step 6: Commit**

```bash
git add ansible_core/store
git commit -m "Add messenger local store"
```

## Task 4: App Relay Client

**Files:**

- Create `ansible_node/app/lib/services/messenger_relay_client.dart`
- Test `ansible_node/app/test/messenger_relay_client_test.dart`

- [ ] **Step 1: Write failing relay client test**

Create test proving exact endpoint URLs and JSON bodies:

```dart
test('publishes device and sends ciphertext through relay APIs', () async {
  final requests = <Uri>[];
  final client = MessengerRelayClient(
    relayBaseUrl: Uri.parse('http://localhost:4001'),
    httpClient: FakeHttpClient((request) async {
      requests.add(request.url);
      return FakeHttpResponse.json(201, {'accepted': true});
    }),
  );

  await client.publishDevice(
    subjectDid: 'did:plc:alice',
    deviceId: 'msgdev_alice',
    bundle: {'messenger_identity_key': 'alice_identity'},
    binding: {'subject_did': 'did:plc:alice'},
    bindingSignature: 'dev-signature',
  );

  await client.sendMessage(
    messageId: 'msg_test',
    senderDid: 'did:plc:alice',
    senderDeviceId: 'msgdev_alice',
    recipientDid: 'did:plc:bob',
    recipientDeviceId: 'msgdev_bob',
    ciphertextType: 'pre_key_signal_message',
    ciphertext: 'base64-ciphertext',
    protocolVersion: 'signal-mvp-v1',
    createdAt: DateTime.utc(2026, 5, 14),
    requestSignature: 'dev-signature',
  );

  expect(requests[0].path, '/api/v1/messenger/devices');
  expect(requests[1].path, '/api/v1/messenger/messages');
});
```

- [ ] **Step 2: Implement client methods**

Implement:

```dart
Future<void> publishDevice({...});
Future<void> publishPreKeys({...});
Future<MessengerPreKeyBundleResponse> fetchPreKeyBundle(String subjectDid);
Future<void> sendMessage({...});
Future<MessengerMailboxResponse> pullMailbox({required String recipientDeviceId, String? cursor});
Future<void> ackMessage({required String messageId, required String recipientDid, required String recipientDeviceId, required String requestSignature});
```

- [ ] **Step 3: Run app service tests**

Run:

```bash
cd ansible_node/app
flutter test test/messenger_relay_client_test.dart
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add ansible_node/app/lib/services/messenger_relay_client.dart ansible_node/app/test/messenger_relay_client_test.dart
git commit -m "Add app messenger relay client"
```

## Task 5: App Messenger Device Service

**Files:**

- Create `ansible_node/app/lib/services/messenger_crypto_bridge.dart`
- Create `ansible_node/app/lib/services/messenger_device_service.dart`
- Test `ansible_node/app/test/messenger_device_service_test.dart`

- [ ] **Step 1: Write failing device service test**

Test behavior:

- Creates a local messenger device when none exists.
- Stores private key reference locally.
- Publishes public bundle and pre-keys to relay.
- Signs binding using existing `DidSigner`.

- [ ] **Step 2: Implement `MessengerCryptoBridge`**

Wrap generated Rust APIs:

```dart
abstract interface class MessengerCryptoBridge {
  Future<MessengerDeviceBundle> createDevice(String subjectDid);
  Future<List<MessengerPreKey>> generatePreKeys(MessengerDeviceBundle device, int count);
  Future<MessengerCiphertext> encryptInitialMessage(MessengerEncryptRequest request);
  Future<MessengerPlaintext> decryptInboundMessage(MessengerDecryptRequest request);
}
```

The concrete implementation calls the Flutter Rust Bridge generated methods
from `ansible_did`'s Rust binding path until a dedicated package boundary exists.

- [ ] **Step 3: Implement `MessengerDeviceService`**

Implement:

```dart
Future<MessengerDeviceRecord> ensurePublishedDevice({
  required String subjectDid,
  required DidSigner didSigner,
});
```

Rules:

- Reuse an existing local device if present.
- Generate and publish 20 one-time pre-keys when fewer than 5 unpublished keys
  remain.
- Sign the messenger binding with `DidSigner.sign`.
- Never send private keys to relay.

- [ ] **Step 4: Run tests**

Run:

```bash
cd ansible_node/app
flutter test test/messenger_device_service_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ansible_node/app/lib/services/messenger_crypto_bridge.dart ansible_node/app/lib/services/messenger_device_service.dart ansible_node/app/test/messenger_device_service_test.dart
git commit -m "Add app messenger device service"
```

## Task 6: App Messenger Sync Service

**Files:**

- Create `ansible_node/app/lib/services/messenger_sync_service.dart`
- Test `ansible_node/app/test/messenger_sync_service_test.dart`

- [ ] **Step 1: Write failing Alice-to-Bob service test**

Use fake crypto, fake relay client, and in-memory repository to prove orchestration:

```dart
test('sends and receives encrypted text without relay plaintext', () async {
  final relay = FakeMessengerRelayClient();
  final alice = MessengerSyncService(...);
  final bob = MessengerSyncService(...);

  await bob.ensureReady(subjectDid: 'did:plc:bob');
  await alice.sendText(
    senderDid: 'did:plc:alice',
    recipientDid: 'did:plc:bob',
    text: 'hello bob',
  );

  expect(relay.acceptedCiphertexts.single.ciphertext, isNot(contains('hello bob')));

  await bob.pullAndDecrypt(recipientDid: 'did:plc:bob');
  final messages = await bob.messagesForConversation('did:plc:alice');
  expect(messages.single.plaintext, 'hello bob');
});
```

- [ ] **Step 2: Implement send path**

`sendText` flow:

1. Ensure local device is published.
2. Fetch recipient pre-key bundle.
3. Call Rust bridge `encryptInitialMessage`.
4. Store outbound local message as `pending`.
5. POST ciphertext to relay.
6. Mark outbound message `sent`.

- [ ] **Step 3: Implement receive path**

`pullAndDecrypt` flow:

1. Pull mailbox by local device id and cursor.
2. For each ciphertext, call Rust bridge `decryptInboundMessage`.
3. Save inbound plaintext locally.
4. Save updated session state.
5. Ack only after successful local save.
6. Store decrypt failures as `decryptFailed` and do not ack.

- [ ] **Step 4: Run tests**

Run:

```bash
cd ansible_node/app
flutter test test/messenger_sync_service_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ansible_node/app/lib/services/messenger_sync_service.dart ansible_node/app/test/messenger_sync_service_test.dart
git commit -m "Add messenger send receive orchestration"
```

## Task 7: Inbox And Thread UI MVP

**Files:**

- Modify `ansible_node/app/lib/screens/inbox_screen.dart`
- Create `ansible_node/app/lib/screens/messenger_thread_screen.dart`
- Test `ansible_node/app/test/inbox_screen_test.dart`
- Test `ansible_node/app/test/messenger_thread_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Tests must verify:

- Empty inbox still renders when there are no conversations.
- Conversation list renders latest local message.
- Thread screen renders inbound and outbound bubbles.
- Composer calls `MessengerSyncService.sendText`.
- Decrypt-failed messages render a non-destructive error row.

- [ ] **Step 2: Implement inbox conversation list**

Keep the current `InboxScreen` shell and replace `_EmptyInbox` only when
repository data contains conversations.

Render:

- DID short label.
- Latest message preview.
- Timestamp.
- Unread count when present.

- [ ] **Step 3: Implement thread screen**

`MessengerThreadScreen` accepts:

```dart
const MessengerThreadScreen({
  super.key,
  required this.conversationId,
  required this.messengerService,
});
```

It renders:

- Message list.
- Text composer.
- Send button disabled for empty text.
- Error banner for send/decrypt failures.

- [ ] **Step 4: Run widget tests**

Run:

```bash
cd ansible_node/app
flutter test test/inbox_screen_test.dart test/messenger_thread_screen_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ansible_node/app/lib/screens/inbox_screen.dart ansible_node/app/lib/screens/messenger_thread_screen.dart ansible_node/app/test/inbox_screen_test.dart ansible_node/app/test/messenger_thread_screen_test.dart
git commit -m "Add encrypted messenger UI shell"
```

## Task 8: End-To-End Local Smoke Harness

**Files:**

- Create `ansible_node/app/test/messenger_e2e_harness_test.dart`
- Modify docs if local run commands change.

- [ ] **Step 1: Add integration harness test**

The test uses in-memory relay/store fakes plus real Rust crypto bridge when
available:

```dart
test('Alice sends encrypted message to Bob through relay mailbox', () async {
  final harness = MessengerE2eHarness.withInMemoryRelay();
  await harness.createIdentity('alice');
  await harness.createIdentity('bob');
  await harness.publishMessengerDevice('alice');
  await harness.publishMessengerDevice('bob');

  await harness.sendText(from: 'alice', to: 'bob', text: 'hello bob');
  expect(harness.relayCiphertexts.single, isNot(contains('hello bob')));

  await harness.pullAndDecrypt('bob');
  expect(await harness.messages('bob', withDid: harness.did('alice')), ['hello bob']);
});
```

- [ ] **Step 2: Run full verification**

Run:

```bash
cargo test -p ansible_rust_core
cd ansible_relay/phoenix && mix test
cd ../../ansible_core/store && dart test
cd ../../ansible_node/app && flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add ansible_node/app/test/messenger_e2e_harness_test.dart docs
git commit -m "Add encrypted messenger smoke harness"
```

## Implementation Notes

- Keep relay ciphertext fields opaque. Do not parse or validate Signal internals
  in Elixir.
- Keep DID signing separate from messenger encryption keys.
- Store private messenger key material only in the app local boundary.
- Do not add group messaging, attachments, push notifications, or sealed sender
  in this plan.
- If the crypto dependency spike fails for mobile targets, stop after Task 1
  and update the spec with the chosen replacement before changing relay or UI.

## Self-Review

- Spec coverage: Rust crypto boundary, relay API, local store, app services, UI,
  failure handling, and MVP exclusions are mapped to tasks.
- Placeholder scan: no open placeholders are left in the plan.
- Type consistency: protocol names use `signal-mvp-v1`,
  `pre_key_signal_message`, `MessengerDevice`, `MessengerPreKeyBundle`,
  `MessengerCiphertext`, and `MessengerPlaintext` consistently.
