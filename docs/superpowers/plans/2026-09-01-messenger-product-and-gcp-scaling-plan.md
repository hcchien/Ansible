# Messenger Product And GCP Scaling Plan

> Status: Phases 1-2 implemented for the contained 1:1 scope; production
> cryptography review remains a release gate; Phases 4-6 remain blocked on the
> Phase 0 product gate  
> Date: 2026-09-01  
> Scope: Signal-style 1:1 encrypted messaging, Instagram-like messaging
> extensions, Phoenix server boundaries, and GCP deployment and scaling

## Goal

Evolve the existing 1:1 encrypted messenger into a reliable mobile messaging
product without giving the server message plaintext, attachment keys, long-term
private messaging keys, or the ability to silently impersonate a device.

The target architecture is **server-assisted end-to-end encryption**, not a
pure P2P messenger. Clients own encryption, decryption, plaintext, local search,
and session state. The server is an opaque key directory, ciphertext mailbox,
delivery coordinator, and abuse-control boundary.

## Phase 0 Product Gate

`docs/ROADMAP.md` currently says Messenger expansion is contained at the 1:1
MVP and explicitly freezes groups, media, and read receipts. This plan does not
silently override that decision.

Before implementing anything beyond reliability and security work for the
existing 1:1 MVP, the product owner must explicitly choose one of these:

1. Keep Messenger contained and execute only Phases 1-3.
2. Promote Messenger to an active product track and permit Phases 4-6.

Until that decision is recorded in the roadmap, groups, media, read receipts,
typing indicators, disappearing messages, voice/video, and federation remain
proposal-only.

## Current Baseline

The repository already contains the beginning of the recommended architecture:

- Signal-style protocol and client/server boundary design in
  `docs/superpowers/specs/2026-05-14-encrypted-messenger-protocol-design.md`.
- Contact discovery design in
  `docs/superpowers/specs/2026-05-14-messenger-contact-discovery-design.md`.
- Phoenix messenger routes and controller.
- Ecto-backed device, pre-key, ciphertext mailbox, and acknowledgement storage.
- PostgreSQL messenger migrations and controller tests.
- Content-free messenger push wake scheduling.

This is an opaque-transport MVP, not yet a complete Signal/libsignal-grade,
multi-device messenger. Existing protocol claims must remain limited until the
client cryptography dependency, test vectors, key-change behavior, device
revocation, and recovery paths pass independent security review.

## Implementation Status (2026-09-01)

The contained Phase 1-2 hardening slice is implemented:

- active-device enforcement for pre-key publication, send, mailbox, and ACK;
- DID-signed device revocation with immediate pre-key removal;
- revoked and expired devices excluded from availability and bundle lookup;
- atomic one-time pre-key reservation remains protected by row locking;
- idempotent same-payload message retries and conflicting-ID rejection;
- opaque cursor mailbox pagination;
- configurable ciphertext retention with expired message/ACK cleanup;
- Flutter fan-out of one logical message to every recipient device that has a
  reserved one-time pre-key;
- separate local session state per local/remote device pair;
- local one-time pre-key loading and consumed-key marking after decryption;
- random non-zero pre-key identifiers across replenishment batches;
- trust-on-first-use remote device key pinning with fail-closed key-change
  detection;
- client API and service support for DID-signed device revocation;
- Rust replay/pre-key uniqueness tests, Flutter fan-out/key-substitution tests,
  and Phoenix controller coverage for revocation and retry idempotency.

The current Rust implementation is still a custom X25519/HKDF/XChaCha20 initial
pre-key envelope identified on the wire as `signal-mvp-v1`. It is **not** a
complete Signal Protocol implementation and has no Double Ratchet for ongoing
messages. The label remains only for wire compatibility with existing MVP data.
Production must not market it as Signal-grade or enable it for sensitive use
until the audited-library dependency spike, protocol replacement/migration,
cross-client test vectors, and independent cryptographic review are complete.

## Architecture Decision

Use Elixir/Phoenix for the Messenger server. Initially keep Messenger as a
well-separated context inside the existing `ansible-relay` deployable:

```text
App / Wallet
  - DID identity authorizes messaging devices
  - per-device messaging keys and ratchet state
  - plaintext, local search, and attachment keys
              |
              | HTTPS / optional foreground Phoenix Channel
              v
Cloud Run: ansible-relay
  - device and pre-key directory
  - opaque ciphertext mailbox
  - delivery ACK, retry, cursor, and TTL
  - content-free push wake scheduling
  - blocking, rate limits, and message-request controls
       |                 |                    |
       v                 v                    v
Cloud SQL          Memorystore Redis     Cloud Storage
metadata and       cross-instance        encrypted
ciphertext         realtime/rate limit   attachments
```

Do not create a separate `ansible-messenger` service at the start. Preserve
module and table ownership boundaries so extraction later changes deployment,
not the protocol. Extract it only when at least one of these becomes true:

- Messenger and Relay need materially different release cadence or SLOs.
- Messenger traffic dominates Relay capacity or database load.
- Security or regulatory isolation requires separate IAM and data stores.
- A second Relay implementation needs the Messenger service independently.

## Why Not Pure P2P

Pure P2P is not the reliable transport for an Instagram-like mobile experience:

- recipients must receive messages while offline;
- iOS and Android suspend background processes;
- NAT, CGNAT, and firewalls make direct connectivity unreliable;
- direct connections can expose peer IP addresses;
- multi-device fan-out and device revocation need durable coordination;
- APNs and FCM are still required to wake background apps.

P2P may be added later for active voice/video calls or optional large-file
transfer. Even then, signaling and STUN/TURN remain server-assisted, and the
mailbox remains the reliable fallback.

## Cryptographic And Identity Boundary

- The DID root identity authorizes messaging device keys but is not used as a
  daily Double Ratchet key.
- Every device has a separately revocable messaging identity and session set.
- Private keys remain in platform secure hardware where supported, or in an
  explicitly labeled reduced-trust mode.
- The client uses an audited Signal-compatible implementation behind the Rust
  facade; application code must not assemble cryptographic primitives itself.
- Asynchronous session establishment uses published signed pre-keys and
  one-time pre-keys.
- Each sender encrypts separately for every active recipient device.
- Key changes, new devices, and revocations are visible to affected users.
- The server never receives plaintext, private keys, attachment keys, or local
  search indexes.

Before selecting or upgrading the Signal-compatible library, run a dependency
spike for supported Rust, Flutter Rust Bridge, iOS, Android, macOS, Windows, and
Linux targets. Pin the reviewed version and keep protocol compatibility tests.

## Reliable Delivery Model

The durable path is HTTP mailbox synchronization, not WebSocket delivery:

1. The sender encrypts an idempotent message event per recipient device.
2. Phoenix accepts the opaque envelope using a unique `message_id`.
3. PostgreSQL persists it before an accepted response is returned.
4. A content-free APNs/FCM event tells the recipient to sync.
5. The recipient pulls by authenticated device and opaque cursor.
6. The recipient decrypts and commits local state before acknowledging.
7. The server removes or tombstones the ciphertext after all required ACKs or
   after its declared TTL.

Phoenix Channels may improve foreground latency. A disconnect always falls
back to cursor catch-up, so reconnects, deploys, and instance replacement do
not lose messages.

## Cloud Run Scaling Plan

Cloud Run is appropriate for the initial and medium-scale service if Phoenix
instances remain stateless and all cross-instance state is external.

### Cloud Run

- Start with the current Cloud Build and Cloud Run deployment path.
- Configure a small non-zero minimum instance count for latency-sensitive
  production traffic.
- Set maximum instances from the Cloud SQL connection budget, not only request
  volume.
- Tune request concurrency using load tests for HTTP and WebSocket workloads.
- Make every write idempotent because clients retry after network failure.
- Treat session affinity as an optimization, never a correctness dependency.
- WebSocket clients must reconnect and cursor-catch-up after timeout or loss.

### Cloud SQL PostgreSQL

- Keep device metadata, pre-keys, ciphertext envelopes, ACKs, and durable job
  state in PostgreSQL.
- Preserve unique constraints for device bindings, pre-key consumption, and
  message IDs.
- Index mailbox reads by recipient device plus monotonic cursor/order key.
- Compute `max_instances * POOL_SIZE` against the database connection budget.
- Add managed pooling or PgBouncer before increasing instance counts beyond
  that budget.
- Partition or archive ciphertext tables only after measured volume requires
  it; TTL deletion is required from the first production release.

### Redis And Background Work

- Use Memorystore Redis for cross-instance rate limiting.
- Use Redis Pub/Sub or another external broadcast adapter for foreground
  realtime events across Cloud Run instances.
- Do not rely on process-local `Phoenix.PubSub` for multi-instance delivery.
- Move retryable delivery and cleanup work to Oban with queue limits,
  backpressure, retry policy, and dead-letter visibility.
- Reconsider GCP Pub/Sub or NATS only for multi-region or independently
  deployed services; it is not required for the first single-region release.

### Attachments

- Generate a random attachment key on the sender device.
- Encrypt before upload and store only ciphertext in Cloud Storage.
- Put the object locator, digest, MIME metadata, and decryption key inside the
  end-to-end encrypted message.
- Use short-lived signed upload/download URLs and lifecycle deletion rules.
- Do not put attachment keys or plaintext filenames in server logs.

## Product Delivery Phases

### Phase 1: Audit And Stabilize Existing 1:1 MVP

Implementation status: completed for transport, storage, replay, retention,
logging boundary, and current-protocol test coverage. Production security
sign-off remains blocked on replacing/reviewing the custom MVP cryptography.

- Inventory the landed server, Rust, Flutter, and Drift implementation against
  the existing protocol spec.
- Confirm the actual crypto implementation and remove unsupported security
  claims.
- Add official/cross-client test vectors, replay tests, pre-key race tests, and
  mailbox authorization tests.
- Define ciphertext and metadata retention policy.
- Verify that logs, metrics, crash reports, and push payloads cannot contain
  message content.

Exit: two clean app installations can exchange 1:1 encrypted text, restart,
retry, and recover mailbox state without server plaintext access.

### Phase 2: Multi-Device And Key Safety

Implementation status: completed for server-side multi-device registration,
fan-out, per-device sessions, revocation, pre-key lifecycle, and fail-closed
remote identity-key changes. A dedicated safety-number/key-change approval UI
is deferred because the contained 1:1 UI currently fails closed instead of
permitting an in-place trust reset.

- Authorize each messaging device from the portable DID identity.
- Encrypt separately for every recipient device.
- Add device list, last-seen metadata minimization, revocation, and key-change
  UX.
- Replenish and rotate pre-keys safely.
- Define recovery behavior without making the server a decryption authority.

Exit: adding or revoking one device does not expose root keys, impersonate the
user, or prevent remaining devices from communicating.

### Phase 3: Production Delivery And GCP Scale

- Deploy the Phoenix context on Cloud Run with explicit concurrency,
  min/max-instance, database pool, timeout, and secret settings.
- Add Oban mailbox cleanup/delivery jobs and Redis-backed abuse controls.
- Add content-free push wake-up, cursor catch-up, SLOs, dashboards, and alerts.
- Load-test send, sync, ACK, reconnect, pre-key reservation, and TTL deletion.

Exit: horizontally scaled instances pass failure/retry tests and remain within
the Cloud SQL connection and latency budgets.

### Phase 4: Instagram-Like 1:1 Experience

Blocked until the Phase 0 product gate permits expansion.

- Message requests and sender controls.
- Replies, reactions, edit, and retract as encrypted events.
- Read receipts and typing state as optional encrypted control events.
- Disappearing-message policy with both client timers and ciphertext TTL.
- Encrypted attachments, local thumbnails, and local-only search.
- User-initiated reporting that selectively discloses chosen evidence.

Exit: every new event type remains opaque to the server, has deterministic
ordering/idempotency behavior, and has user-visible privacy controls.

### Phase 5: Groups

Blocked until the Phase 0 product gate permits expansion and a separate group
protocol review is approved.

- Select a reviewed Sender Keys-style or MLS-based design based on measured
  group size and membership-change requirements.
- Rotate group keys on membership changes.
- Prevent removed members from receiving later keys.
- Do not give new members historical plaintext by default.
- Define group governance, invitations, blocking, reporting, and recovery.

### Phase 6: Calls, P2P, And Federation

- Add WebRTC only for active media sessions or optional large-file transfer.
- Operate signaling and STUN/TURN without treating direct connectivity as
  guaranteed.
- Keep encrypted mailbox fallback for call invitations and delivery.
- Design cross-relay messaging separately, including remote host compliance,
  metadata leakage, spam controls, and failure semantics.

## Metadata And Abuse Controls

End-to-end encryption does not hide the social graph by itself. Minimize:

- source and destination identifiers retained in delivery logs;
- IP address retention;
- exact ciphertext sizes, using bounded padding where practical;
- push tokens and device metadata;
- pre-key lookup history and availability probes.

Use message requests, local block lists, per-device and per-identity rate
limits, and reason-coded temporary restrictions. Reporting must be explicit:
the user selects the messages and context to disclose. There must be no routine
server-side decryption or universal moderation backdoor.

## Verification And Operations

At minimum, CI and staging must cover:

- server never persists or logs test plaintext;
- one-time pre-key reservation is atomic under concurrency;
- mailbox access is bound to the recipient DID and authorized device;
- duplicate sends and ACKs are idempotent;
- process restart and instance replacement do not lose accepted ciphertext;
- WebSocket loss recovers through cursor sync;
- push payloads contain only an opaque sync hint;
- expired and acknowledged ciphertext is deleted according to policy;
- revoked devices cannot fetch later messages or publish fresh pre-keys;
- database and Redis degradation fail according to documented privacy and
  delivery semantics.

Production dashboards should include aggregate mailbox write/read/ACK latency,
queue depth, ciphertext age, pre-key availability, retry/dead-letter count,
rate-limit outcomes, active WebSocket connections, DB pool saturation, and
Cloud Run instance count. Labels must not contain DIDs, device IDs, message IDs,
or ciphertext.

## Constitution Review

This plan touches identity, storage, sync, federation, moderation, and Relay
behavior. It was reviewed against the Tris-Aura Engineering Constitution and
the current compliance review.

1. **Identity autonomy:** DID identity remains portable and authorizes
   separately revocable messaging devices. The Relay is not the sole identity
   authority and never holds private identity or messaging keys.
2. **Data autonomy:** plaintext, local search, ratchet state, and attachment
   keys remain local. Private data is encrypted before leaving the trusted
   device boundary, and all private paths fail closed.
3. **Minimal disclosure:** messaging does not require legal identity or a
   high-assurance personhood credential. Any anti-abuse tier check uses only
   the minimum claim needed.
4. **Integrity and Sybil resistance:** lower-trust senders may receive stricter
   message-request and rate-limit policy, but enforcement is reason-coded and
   does not reveal or depend on raw legal identity.
5. **Moderation:** blocking is local/user-controlled. Reports disclose only
   user-selected evidence. No server decryption key or silent exception path is
   introduced.
6. **Federation:** private-message federation is deferred to a separate review.
   External Messenger hosts must expose constitution compliance level before
   first-party clients rely on their storage or metadata behavior.

The current compliance review still identifies incomplete hardware-backed key
coverage and incomplete persistence/policy use of external-host compliance.
Those gaps prevent a claim that the expanded Messenger is fully constitution
compliant. Unsupported platforms must remain explicitly reduced-trust, and
cross-relay messaging must not launch until the relevant host-compliance policy
is implemented.

## Decision Summary

- **Server:** Elixir/Phoenix.
- **Initial deployable:** existing `ansible-relay`, with strict Messenger
  module and table boundaries.
- **Compute:** GCP Cloud Run, stateless horizontal instances.
- **Durability:** Cloud SQL PostgreSQL.
- **Cross-instance realtime and rate limiting:** Memorystore Redis.
- **Jobs:** Oban; consider Pub/Sub/NATS only at multi-region/service extraction.
- **Attachments:** client-encrypted Cloud Storage objects.
- **Reliability source:** durable HTTP cursor mailbox; Phoenix Channels are a
  foreground latency optimization.
- **P2P:** optional later for calls or large transfers, never the only delivery
  path.
- **Expansion status:** Phases 4-6 require an explicit roadmap decision.
