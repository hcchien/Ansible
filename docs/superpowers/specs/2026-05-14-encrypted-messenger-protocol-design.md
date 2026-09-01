# Encrypted Messenger Protocol Design Spec

> Status: Draft for implementation planning  
> Date: 2026-05-14  
> Scope: app-held messenger crypto, Rust API boundary, Flutter app services,
> Elixir/Phoenix relay mailbox APIs, local store schema, and 1:1 encrypted text
> messaging

## Goal

Add a 1:1 encrypted messenger path where users can send private text messages
through the relay without giving the relay plaintext or long-term private keys.

The relay remains an opaque transport and directory. The app owns all private
cryptographic state. The Rust layer owns the messenger crypto boundary. Dart
orchestrates storage, network calls, and UI state.

## Current Context

Existing useful pieces:

- `ansible_rust_core` exposes Ed25519 DID key generation and signing through
  Flutter Rust Bridge.
- The app already depends on `ansible_did`, `ansible_store`, local Drift
  storage, `flutter_secure_storage`, and HTTP clients.
- The relay already verifies Ed25519 DID signatures for identity anchoring,
  publication intents, and web-session grants.
- The relay already has a Plug router and in-memory stores for dev-grade
  challenge/session flows.

Missing pieces:

- No X25519/Signal identity keys.
- No pre-key bundle publication or lookup.
- No one-time pre-key consumption.
- No Double Ratchet session state.
- No local conversation/message store.
- No opaque encrypted message mailbox on the relay.
- No messenger UI beyond an empty inbox placeholder.

## Security Decision

Use a Signal-style asynchronous protocol shape:

- X3DH-style pre-key session setup.
- Double Ratchet-style message sessions after setup.
- Sesame-style device and session management rules for offline delivery.

Do not hand-roll these primitives. The implementation must sit behind an
`ansible_rust_core` messenger facade so the app can switch the underlying Rust
Signal implementation without changing Dart, relay, or UI contracts.

Official Signal `libsignal` is the reference direction, but its README states
that use outside Signal is unsupported and APIs can change. The first execution
slice must therefore include a dependency spike that proves the chosen Rust
library can build for the app targets and expose the required operations through
Flutter Rust Bridge.

Source references:

- `https://github.com/signalapp/libsignal`
- `https://signal.org/docs/specifications/x3dh/`
- `https://signal.org/docs/specifications/doubleratchet/`
- `https://signal.org/docs/specifications/sesame/`

## Identity And Key Model

The DID signing key and the messenger encryption identity are separate.

| Key | Algorithm / Role | Owner | Stored Where |
|---|---|---|---|
| DID signing key | Ed25519 signing and DID anchoring | App | existing DID storage path |
| Messenger identity key | Signal-compatible identity key for E2EE | App | secure storage + local key store metadata |
| Signed pre-key | Medium-lived pre-key signed by DID and messenger identity | App publishes public part | relay stores public bundle only |
| One-time pre-key | Single-use pre-key for offline session start | App publishes public part | relay stores public keys until consumed |
| Ratchet session state | Per remote device conversation crypto state | App | local encrypted store where practical |

The DID key signs a messenger device binding:

```json
{
  "type": "io.trisaura.messengerDeviceBinding",
  "version": 1,
  "subject_did": "did:plc:...",
  "device_id": "msgdev_...",
  "messenger_identity_key": "base64-public-key",
  "signed_pre_key_id": 42,
  "signed_pre_key": "base64-public-key",
  "created_at": "2026-05-14T00:00:00Z",
  "expires_at": "2026-06-13T00:00:00Z"
}
```

The relay verifies the DID signature before accepting or returning a device
bundle. The relay never receives private messenger keys or plaintext.

## MVP Scope

The first messenger milestone is 1:1 text only.

Included:

- One local device per DID.
- Publish messenger device bundle.
- Publish signed pre-key and a small batch of one-time pre-keys.
- Fetch recipient pre-key bundle.
- Encrypt an initial text message for one recipient device.
- Store ciphertext on relay.
- Recipient pulls pending ciphertext messages.
- Recipient decrypts, stores plaintext locally, and acknowledges delivery.
- Local conversation list and message thread backed by Drift.

Excluded from MVP:

- Group messaging.
- Attachments.
- Voice/video.
- Multi-device fanout.
- Sealed sender.
- Contact discovery privacy.
- Push notifications.
- Message backup and device migration.
- Disappearing messages.
- Safety number UI.
- Cross-relay federation for private messages.

## Relay Responsibilities

The relay is an untrusted transport with abuse controls.

It owns:

- Public messenger device registry.
- Pre-key bundle lookup.
- One-time pre-key reservation and consumption.
- Opaque encrypted message mailbox.
- Delivery acknowledgement and cursor-based polling.
- Rate limits for bundle publish, bundle fetch, and mailbox writes.

It must not:

- Accept plaintext message bodies.
- Store private keys.
- Decrypt ciphertext.
- Rewrite cryptographic headers.
- Claim message authenticity beyond "accepted from authenticated DID/device".

## Relay API Contract

All write APIs require DID authentication. The first implementation may reuse
the existing DID-auth pattern used by publication intents or web-session grants.

### Publish Device Bundle

`POST /api/v1/messenger/devices`

Request:

```json
{
  "subject_did": "did:plc:...",
  "device_id": "msgdev_...",
  "bundle": {
    "messenger_identity_key": "base64-public-key",
    "signed_pre_key_id": 42,
    "signed_pre_key": "base64-public-key",
    "signed_pre_key_signature": "base64-signature",
    "expires_at": "2026-06-13T00:00:00Z"
  },
  "binding": {},
  "binding_signature": "hex-ed25519"
}
```

Response:

```json
{
  "accepted": true,
  "subject_did": "did:plc:...",
  "device_id": "msgdev_..."
}
```

### Publish One-Time Pre-Keys

`POST /api/v1/messenger/pre-keys`

Request:

```json
{
  "subject_did": "did:plc:...",
  "device_id": "msgdev_...",
  "pre_keys": [
    {"pre_key_id": 1001, "pre_key": "base64-public-key"}
  ],
  "request_signature": "hex-ed25519"
}
```

### Fetch Recipient Bundle

`GET /api/v1/messenger/pre-key-bundles/:subject_did`

This consuming read requires an authenticated active sender device. Query
parameters are `sender_did`, `sender_device_id`, `request_id`, and
`request_signature`. The signature covers:

```json
{
  "recipient_did": "did:plc:bob",
  "sender_did": "did:plc:alice",
  "sender_device_id": "msgdev_alice",
  "request_id": "msg_..."
}
```

`request_id` is stable for one logical send. Retrying the same signed request
returns the same reserved one-time pre-key instead of consuming another key.
The relay rate-limits reservations per authenticated sender DID.

Response:

```json
{
  "subject_did": "did:plc:...",
  "devices": [
    {
      "device_id": "msgdev_...",
      "messenger_identity_key": "base64-public-key",
      "signed_pre_key_id": 42,
      "signed_pre_key": "base64-public-key",
      "signed_pre_key_signature": "base64-signature",
      "one_time_pre_key_id": 1001,
      "one_time_pre_key": "base64-public-key",
      "binding": {},
      "binding_signature": "hex-ed25519"
    }
  ]
}
```

The relay removes a returned one-time pre-key from the available pool.

### Send Ciphertext

`POST /api/v1/messenger/messages`

Request:

```json
{
  "message_id": "msg_...",
  "sender_did": "did:plc:alice",
  "sender_device_id": "msgdev_alice",
  "recipient_did": "did:plc:bob",
  "recipient_device_id": "msgdev_bob",
  "ciphertext_type": "pre_key_signal_message",
  "ciphertext": "base64-bytes",
  "protocol_version": "signal-mvp-v1",
  "created_at": "2026-05-14T00:00:00Z",
  "request_signature": "hex-ed25519"
}
```

### Pull Mailbox

`GET /api/v1/messenger/messages?recipient_device_id=msgdev_...&cursor=...`

Response:

```json
{
  "messages": [
    {
      "message_id": "msg_...",
      "sender_did": "did:plc:alice",
      "sender_device_id": "msgdev_alice",
      "recipient_did": "did:plc:bob",
      "recipient_device_id": "msgdev_bob",
      "ciphertext_type": "pre_key_signal_message",
      "ciphertext": "base64-bytes",
      "protocol_version": "signal-mvp-v1",
      "created_at": "2026-05-14T00:00:00Z"
    }
  ],
  "next_cursor": "opaque-cursor"
}
```

### Acknowledge Delivery

`POST /api/v1/messenger/messages/:message_id/ack`

Request:

```json
{
  "recipient_did": "did:plc:bob",
  "recipient_device_id": "msgdev_bob",
  "request_signature": "hex-ed25519"
}
```

## Rust API Boundary

The Rust API surface must expose protocol operations, not raw primitives:

```rust
pub fn api_messenger_create_device(subject_did: String) -> Result<MessengerDeviceBundle, String>;
pub fn api_messenger_generate_pre_keys(count: u32) -> Result<Vec<MessengerPreKey>, String>;
pub fn api_messenger_encrypt_initial_message(input: MessengerEncryptInput) -> Result<MessengerCiphertext, String>;
pub fn api_messenger_decrypt_inbound_message(input: MessengerDecryptInput) -> Result<MessengerPlaintext, String>;
```

Rust owns:

- Messenger identity key generation.
- Pre-key generation.
- Session state serialization.
- Encryption and decryption.
- Ratchet state updates.

Dart owns:

- Persisting serialized session state.
- Calling relay APIs.
- Mapping plaintext into local message records.
- Rendering UI.

## Local Store Model

New Drift tables:

- `messenger_devices`: local and cached remote device metadata.
- `messenger_pre_keys`: local pre-key ids, publish state, and consumption state.
- `messenger_sessions`: per remote device serialized ratchet state.
- `messenger_conversations`: 1:1 conversation metadata.
- `messenger_messages`: local plaintext, ciphertext metadata, direction, status,
  and timestamps.
- `messenger_mailbox_cursor`: per local device relay polling cursor.

Plaintext is local-only. Relay ciphertext is not treated as source of truth after
decryption.

## Error Handling

- Missing local messenger device: app shows setup-required state and offers to
  publish a device bundle.
- No recipient pre-key bundle: composer disables send with a retryable
  "recipient unavailable" state.
- Recipient has no one-time pre-key: app may use signed pre-key fallback only if
  the chosen Signal library supports the safe fallback path.
- Decrypt failure: store ciphertext metadata with `decrypt_failed`, do not ack,
  and surface a non-destructive error.
- Replay or duplicate message id: relay returns the existing accepted message
  response for idempotent sender retries.
- Expired signed pre-key: relay rejects bundle lookup for the device until the
  app republishes a fresh bundle.

## Testing Strategy

Tests must prove:

- Relay never stores plaintext.
- Relay consumes one-time pre-keys at most once.
- Relay mailbox is scoped to recipient device and DID-authenticated.
- Rust round-trip encrypt/decrypt works across two generated devices.
- Dart repositories preserve session state and message ordering.
- App service can run Alice-to-Bob happy path with a fake relay client.
- UI shows setup, empty inbox, send pending, sent, received, and decrypt-failed
  states.

## Acceptance Criteria

- A local Alice app can publish a messenger device bundle.
- A local Bob app can publish a messenger device bundle and one-time pre-keys.
- Alice can fetch Bob's bundle, encrypt a text message, and send ciphertext to
  the relay.
- Bob can pull, decrypt, store, and acknowledge the message.
- The relay never logs or stores plaintext.
- DID signing remains separate from messenger encryption keys.
- All MVP behavior is covered by Rust, Elixir, Dart store, app service, and UI
  tests.
