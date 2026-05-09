# Federation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build full federation E2E by keeping Ansible local-first, publishing public content directly to Nostr from the app, and delegating ActivityPub federation to the relay layer.

**Architecture:** Ansible's local domain model remains canonical. A protocol-neutral publication intent/outbox feeds two adapters: an app-side Nostr adapter and a relay-side ActivityPub adapter. The first gate builds publication abstraction before any external network adapter is allowed to publish content.

**Tech Stack:** Dart, Flutter, Drift, `flutter_secure_storage`, WebSocket Nostr relay protocol, secp256k1 Schnorr signing, Elixir/Phoenix relay, ActivityPub JSON, WebFinger, `dart test`, `flutter test`, `mix test`.

---

## Source Documents

Read these first:

- `docs/protocol/tris_aura_federation_strategy_v0.1.md`
- `docs/superpowers/specs/2026-05-09-federation-strategy-design.md`
- `docs/protocol/tris_aura_sync_spec_v2.0.md`

Important boundaries:

- `ContentItem`, `FollowEdge`, local visibility, and Drift SQLite remain canonical.
- Nostr is app-direct: app owns the Nostr key and publishes signed events to selected relays.
- ActivityPub is relay-managed: app never exposes ActivityPub inbox/outbox endpoints.
- `private` content must never create a Nostr event, ActivityPub activity, or relay publication intent.
- `unlisted` and `public` content may be saved locally before signing succeeds, but external distribution must require a real user private-key signature.
- Stub signatures, dev signatures, and insecure fallback signatures must never be silently accepted on production distribution paths.
- NIP-26 is not part of v1.

## File Structure

Create protocol-neutral publication state:

- `ansible_core/store/lib/src/entities/publication_intent.dart`
- `ansible_core/store/lib/src/entities/publication_target.dart`
- `ansible_core/store/lib/src/entities/identity_binding.dart`
- `ansible_core/store/lib/src/schema/publication_intents.dart`
- `ansible_core/store/lib/src/schema/publication_targets.dart`
- `ansible_core/store/lib/src/schema/identity_bindings.dart`
- `ansible_core/store/lib/src/repositories/publication_repository.dart`
- `ansible_core/store/lib/src/repositories/drift/drift_publication_repository.dart`
- `ansible_core/store/lib/src/repositories/in_memory/in_memory_publication_repository.dart`

Create a new Nostr core package:

- `ansible_core/nostr/pubspec.yaml`
- `ansible_core/nostr/lib/ansible_nostr.dart`
- `ansible_core/nostr/lib/src/nostr_event.dart`
- `ansible_core/nostr/lib/src/nostr_event_signer.dart`
- `ansible_core/nostr/lib/src/nostr_key_store.dart`
- `ansible_core/nostr/lib/src/nostr_identifier.dart`
- `ansible_core/nostr/lib/src/nostr_content_projection.dart`
- `ansible_core/nostr/lib/src/nostr_relay_client.dart`

Modify the app:

- `ansible_node/app/pubspec.yaml`
- `ansible_node/app/lib/services/nostr_publication_service.dart`
- `ansible_node/app/lib/widgets/content_visibility_sheet.dart`
- `ansible_node/app/lib/screens/sync_settings_screen.dart`
- `ansible_node/app/lib/screens/home_shell.dart`

Modify the Phoenix relay for ActivityPub:

- `ansible_relay/phoenix/lib/ansible_relay/activity_pub/actor.ex`
- `ansible_relay/phoenix/lib/ansible_relay/activity_pub/activity_builder.ex`
- `ansible_relay/phoenix/lib/ansible_relay/activity_pub/delivery_queue.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/activity_pub_controller.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/publication_intent_controller.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`

## Task 1: Protocol-Neutral Publication Model

**Files:**

- Create store entities and schemas listed under publication state.
- Modify `ansible_core/store/lib/src/db/app_database.dart`.
- Modify `ansible_core/store/lib/ansible_store.dart`.
- Generate `ansible_core/store/lib/src/db/app_database.g.dart`.
- Test `ansible_core/store/test/publication_repository_test.dart`.

- [x] Add `PublicationIntent` with fields: `intentId`, `authorDid`, `contentItemId`, `action` (`publish`, `update`, `delete`), `visibility`, `status`, `createdAt`, `updatedAt`, and `error`.
- [x] Add `PublicationTarget` with fields: `targetId`, `intentId`, `protocol` (`nostr`, `activityPub`), `endpoint`, `status`, `remoteId`, `lastAttemptAt`, and `error`.
- [x] Add `IdentityBinding` with fields: `bindingId`, `localAccountDid`, `bindingType` (`nostr`, `activityPub`, `nip05`, `atproto`), `identifier`, `publicKey`, `isPrimary`, `createdAt`, and `updatedAt`.
- [x] Add repository methods: `enqueueIntent`, `listPendingTargets`, `markTargetPublished`, `markTargetFailed`, `markIntentComplete`, and `bindingsForAccount`.
- [x] Add tests proving `private` publication intents are rejected before storage.
- [x] Add a signing policy model that distinguishes unsigned local-only saves from signed distribution attempts.
- [x] Add tests proving `unlisted` and `public` publication targets cannot move to publishable state without a required real-signature marker.
- [x] Run `cd ansible_core/store && dart test test/publication_repository_test.dart`.
- [ ] Commit with `feat(store): add federation publication outbox`.

## Task 2: Nostr Core Package

**Files:**

- Create the `ansible_core/nostr` package files listed above.
- Add it as a path dependency in `ansible_node/app/pubspec.yaml`.
- Test `ansible_core/nostr/test/nostr_event_test.dart`.
- Test `ansible_core/nostr/test/nostr_identifier_test.dart`.

- [x] Implement NIP-01 event serialization: `id = sha256([0, pubkey, created_at, kind, tags, content])` with compact UTF-8 JSON.
- [x] Implement `NostrEvent` fields: `id`, `pubkey`, `createdAt`, `kind`, `tags`, `content`, and `sig`.
- [x] Implement `NostrEventSigner` behind an interface so production secp256k1 Schnorr signing can be swapped without changing projections.
- [x] Implement `NostrKeyStore` using secure storage for local private key material.
- [x] Reject stub/dev signatures unless an explicit test-only signer is injected by tests.
- [x] Add tests proving production signing emits NIP-01-valid signatures and fails closed when key material or native signing is unavailable.
- [x] Implement NIP-19 identifier helpers for `npub`, `note`, `nevent`, and `naddr` display values.
- [x] Add tests using fixed vectors for deterministic serialization and identifier encoding.
- [x] Run `cd ansible_core/nostr && dart test`.
- [ ] Commit with `feat(nostr): add event and identity primitives`.

## Task 3: ContentItem To Nostr Projection

**Files:**

- Create `ansible_core/nostr/lib/src/nostr_content_projection.dart`.
- Test `ansible_core/nostr/test/nostr_content_projection_test.dart`.

- [x] Map public or unlisted `murmur` to NIP-01 `kind:1`.
- [x] Map public or unlisted `note` to NIP-23 `kind:30023` with `d`, `title`, `published_at`, and optional `t` tags.
- [x] Map delete/tombstone to NIP-09 `kind:5` referencing the prior Nostr event id.
- [x] Map follow graph snapshots to NIP-02 `kind:3`.
- [x] Map relay preferences to NIP-65 `kind:10002`.
- [x] Reject `private` content with a typed projection error.
- [x] Add tests for murmur, note, delete, follow, relay list, and private rejection.
- [x] Run `cd ansible_core/nostr && dart test test/nostr_content_projection_test.dart`.
- [ ] Commit with `feat(nostr): project content into nostr events`.

## Task 4: App-Side Nostr Publish And Read

**Files:**

- Create `ansible_node/app/lib/services/nostr_publication_service.dart`.
- Modify `ansible_node/app/lib/screens/sync_settings_screen.dart`.
- Modify `ansible_node/app/lib/widgets/content_visibility_sheet.dart`.
- Test `ansible_node/app/test/nostr_publication_service_test.dart`.
- Test `ansible_node/app/test/distribution_settings_test.dart`.

- [x] Add relay settings for read/write Nostr relays.
- [x] Add `NostrPublicationService` that reads pending Nostr targets, signs projected events, publishes via WebSocket, and records per-relay success/failure.
- [x] Add minimal NIP-01 relay client support for `EVENT`, `REQ`, `EOSE`, `OK`, `NOTICE`, and `CLOSE`.
- [x] Ensure partial relay success does not fail the whole intent.
- [x] Ensure failed relay targets remain retryable.
- [x] Ensure no private content can reach `NostrPublicationService`.
- [x] Ensure public/unlisted content without a real Nostr private-key signature remains local and records an explicit pending/failed publication status instead of using a dev fallback.
- [x] Run `cd ansible_node/app && flutter test test/nostr_publication_service_test.dart test/distribution_settings_test.dart`.
- [x] Commit with `feat(app): publish public content to nostr relays`.

## Task 5: Relay Publication Intent Endpoint

**Files:**

- Create `ansible_relay/phoenix/lib/ansible_relay/web/controllers/publication_intent_controller.ex`.
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`.
- Test `ansible_relay/phoenix/test/publication_intent_controller_test.exs`.

- [x] Add `POST /api/v1/publication-intents`.
- [x] Validate signed app publication intent: author id, content id, action, visibility, payload hash, and signature.
- [x] Reject missing, stub, dev, or malformed intent signatures even when the app saved the source content locally.
- [x] Reject private visibility.
- [x] Store accepted intents for ActivityPub delivery.
- [x] Return stable relay-side publication id and initial delivery status.
- [x] Run `cd ansible_relay/phoenix && mix test test/publication_intent_controller_test.exs`.
- [x] Commit with `feat(relay): accept signed publication intents`.

## Task 6: Relay-Side ActivityPub Actor And Delivery

**Files:**

- Create ActivityPub modules and controller listed above.
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`.
- Test `ansible_relay/phoenix/test/activity_pub_controller_test.exs`.
- Test `ansible_relay/phoenix/test/activity_pub_delivery_test.exs`.

- [x] Add WebFinger endpoint for relay-domain actors, e.g. `acct:alice@relay.trisaura.io`.
- [x] Add Actor endpoint under `/users/:actor`.
- [x] Add inbox and outbox endpoints under `/users/:actor/inbox` and `/users/:actor/outbox`.
- [x] Map publication intent `publish` to ActivityPub `Create`.
- [x] Map publication intent `update` to ActivityPub `Update`.
- [x] Map publication intent `delete` to ActivityPub `Delete`.
- [x] Store delivery attempts per remote inbox and retry transient failures.
- [x] Treat external deletes as best-effort while preserving internal tombstones.
- [x] Run `cd ansible_relay/phoenix && mix test test/activity_pub_controller_test.exs test/activity_pub_delivery_test.exs`.
- [ ] Commit with `feat(relay): distribute publications over activitypub`.

## Task 7: UI Distribution Settings

**Files:**

- Modify `ansible_node/app/lib/widgets/content_visibility_sheet.dart`.
- Modify `ansible_node/app/lib/screens/sync_settings_screen.dart`.
- Modify `ansible_node/app/lib/screens/home_shell.dart`.
- Test `ansible_node/app/test/content_visibility_controls_test.dart`.
- Test `ansible_node/app/test/federation_visibility_test.dart`.

- [x] Keep visibility labels simple: private, unlisted, public.
- [x] Add advanced distribution settings for Nostr relays and ActivityPub relay opt-in.
- [x] Ensure private content disables all federation targets.
- [x] Ensure unlisted/public can choose Nostr, ActivityPub, or both.
- [x] Show an explicit pending/failed distribution state when public/unlisted content cannot be signed with the user's real private key.
- [x] Show per-target delivery status without making protocol details prominent in the editor.
- [x] Run `cd ansible_node/app && flutter test test/content_visibility_controls_test.dart test/federation_visibility_test.dart`.
- [x] Commit with `feat(app): add federation distribution controls`.

## Task 8: Migration And Compatibility Cleanup

**Files:**

- Modify tests and fixtures that assume `did:plc` is the only public identity.
- Update docs that mention AT Protocol as the only interoperability target.
- Test full affected suites.

- [ ] Keep current `did:plc` tests valid where they exercise existing local identity flow.
- [ ] Add `did:nostr` fixtures for Nostr public identity.
- [ ] Add ActivityPub actor URL fixtures under relay domain.
- [ ] Update references so `did:plc` is described as current compatibility context, not required federation identity.
- [ ] Run `cd ansible_node/app && flutter test`.
- [ ] Run `cd ansible_core/store && dart test`.
- [ ] Run `cd ansible_core/nostr && dart test`.
- [ ] Run `cd ansible_relay/phoenix && mix test`.
- [ ] Commit with `docs: clarify federation identity transition`.

## Acceptance Checklist

- [ ] App can publish public/unlisted Nostr events directly to configured relays.
- [ ] Relay can receive signed publication intents and project them to ActivityPub.
- [ ] ActivityPub Actor/WebFinger/outbox/inbox endpoints return valid JSON.
- [ ] Private content never produces external protocol payloads.
- [ ] Public/unlisted content is never externally distributed with unsigned, stub-signed, or dev-signed payloads.
- [ ] If production signing is unavailable, content remains locally saved with explicit retryable publication status.
- [ ] NIP-26 remains excluded from v1.
- [ ] Documentation states Nostr and ActivityPub are adapters over the local-first canonical model.
