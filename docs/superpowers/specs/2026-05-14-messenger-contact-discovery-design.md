# Messenger Contact Discovery Design Spec

> Status: Draft for implementation planning  
> Date: 2026-05-14  
> Scope: human-friendly contact identity mapping, handle-to-DID resolution,
> messenger availability discovery, and contact-based message entry points

## Goal

Make encrypted messenger usable without asking normal users to type or recognize
raw DIDs. Users should choose a person by display name, handle, local alias, or
known relationship, while the app resolves the underlying DID and messenger
device public bundle only at the protocol boundary.

## Problem

The current messenger path works when the sender already knows the recipient
`subject_did`. That is technically correct but not user-friendly:

- Raw DIDs are hard to read, type, verify, and remember.
- Nicknames are not globally unique and are easy to impersonate.
- Messenger send requires the recipient's public messenger device bundle and a
  one-time pre-key, but checking availability should not consume a one-time
  pre-key.
- The app needs a stable local contact list so inbox rows, thread headers,
  profile CTAs, and contact pickers can render the same identity consistently.

## Core Model

Separate identity lookup from messenger encryption.

| Layer | Purpose | Example |
|---|---|---|
| DID | Stable identity anchor used by protocol APIs | `did:plc:abc...` |
| Handle | Human-addressable identifier that resolves to DID | `alice.elix.app` |
| Display name | Public profile label | `Alice Chen` |
| Local alias | Private user-defined override | `設計夥伴 Alice` |
| Relationship | Local/social context | `following`, `mutual`, `board_peer` |
| Messenger capability | Whether a DID has message-capable devices | `available`, `no_devices`, `no_pre_keys` |

Relay/API JSON uses snake_case values. Local Dart enum storage uses Dart enum
names such as `boardPeer`, `noDevices`, `noPreKeys`, and `relayUnavailable`.
Conversion happens only at API DTO boundaries.

The UI must prefer:

1. Local alias.
2. Profile display name.
3. Handle.
4. DID short label as fallback.

DID should appear in detail/safety views, not as the primary label.

## Contact Sources

The first implementation supports known contacts from these sources:

- Manual DID or handle entry.
- Existing follow graph / profile context when available.
- Existing conversation peers.
- Board/discussion participants when later wired in.
- QR or invite link when later wired in.

The MVP does not need a global people search. It only needs a local contact
store and deterministic resolver behavior for known identities.

## Contact Store

The local app store owns contact metadata. The relay is not the source of truth
for local aliases or relationship state.

Minimum contact record:

```json
{
  "subject_did": "did:plc:alice",
  "handle": "alice.elix.app",
  "display_name": "Alice",
  "local_alias": "設計夥伴 Alice",
  "avatar_url": "https://...",
  "relationship": "following",
  "source": "manual",
  "trust_state": "known",
  "created_at": "2026-05-14T00:00:00Z",
  "updated_at": "2026-05-14T00:00:00Z",
  "last_resolved_at": "2026-05-14T00:00:00Z"
}
```

Relationship values:

- `following`
- `follower`
- `mutual`
- `conversation`
- `board_peer`
- `invite`
- `manual`
- `unknown`
- `blocked`

Trust states:

- `known`: Current handle/profile resolution matches stored DID.
- `changed`: A previously stored handle now resolves to a different DID.
- `unverified`: Contact was manually entered but not resolved.
- `blocked`: User blocked this DID locally.

## Handle Resolution

The app should expose a resolver boundary:

```dart
abstract interface class ContactResolver {
  Future<ContactResolution> resolveHandle(String handle);
  Future<ContactResolution> resolveDid(String subjectDid);
}
```

Initial resolution strategy:

1. Normalize user input.
2. If input starts with `did:`, treat it as DID.
3. Otherwise resolve handle to DID through the existing identity/ATProto
   resolver boundary when available.
4. Load local contact metadata.
5. Merge remote profile metadata when available.
6. Persist or update local contact record.
7. Flag identity changes if a handle previously mapped to another DID.

## Messenger Availability

Checking whether a person can receive encrypted messages must not consume a
one-time pre-key.

Add a non-consuming relay endpoint:

```http
GET /api/v1/messenger/devices/:subject_did
```

Response:

```json
{
  "subject_did": "did:plc:alice",
  "devices": [
    {
      "device_id": "msgdev_...",
      "messenger_identity_key": "base64-public-key",
      "signed_pre_key_id": 42,
      "signed_pre_key": "base64-public-key",
      "signed_pre_key_signature": "base64-signature",
      "has_one_time_pre_keys": true,
      "binding": {},
      "binding_signature": "hex-signature"
    }
  ]
}
```

`GET /api/v1/messenger/pre-key-bundles/:subject_did` remains the consuming
endpoint for starting a session. The app should call the consuming endpoint
only when it is actually sending the initial encrypted message.

Availability states:

- `available`: At least one device has a signed pre-key and available one-time
  pre-key.
- `no_devices`: DID has not published messenger devices.
- `no_pre_keys`: DID has device metadata but no one-time pre-keys.
- `blocked`: User blocked this DID locally.
- `unresolved`: Handle/DID lookup failed.
- `relay_unavailable`: Availability could not be checked.

## UX Requirements

### Contact Picker

The user should be able to start a message by selecting a contact, not by
typing a DID.

The contact picker shows:

- Display label.
- Handle when present.
- Relationship badge.
- Messenger availability.
- DID short label only as secondary/debug detail.

### Thread Header

Thread headers show:

- Display label.
- Handle or DID short label as subtitle.
- Messenger availability / safety indicator.

### Profile CTA

Profiles and known identity detail screens should expose "Message" only when:

- The contact is not blocked.
- Messenger availability is `available`.

If unavailable, show a disabled CTA with a reason:

- "尚未啟用私訊"
- "暫時沒有可用的收訊金鑰"
- "此聯絡人已封鎖"

### Identity Safety

If a handle that was previously associated with DID A resolves to DID B:

- Do not silently update the existing contact.
- Mark the contact as `changed`.
- Disable message send until the user confirms the identity change.
- Show both old DID short label and new DID short label in the safety detail.

## Security And Privacy Requirements

- Never use nickname alone as identity.
- Never consume one-time pre-keys for contact list rendering.
- Never expose local alias to relay.
- Do not upload full contact lists to relay.
- Contact list is local-first.
- Messenger availability checks can reveal interest in a DID; batch or cache
  later if this becomes a privacy issue.
- Blocked contacts must not be suggested in the message composer.

## MVP Scope

Included:

- Local contact store.
- Contact resolver for DID and handle-shaped input.
- Messenger availability resolver.
- Non-consuming relay device availability endpoint.
- Inbox/thread labels backed by contact resolution.
- Contact picker entry point for starting a thread.
- Widget and integration tests.

Excluded:

- Global people search.
- Contact list upload/sync.
- Push notifications.
- Safety number QR ceremony.
- Group messaging.
- Cross-relay private message discovery.
- Rich profile federation.
- Contact import from phone address book.

## Acceptance Criteria

- A user can add a contact by handle or DID.
- The app stores DID-to-human-label mapping locally.
- Inbox and thread headers render human-readable labels instead of raw DID when
  contact metadata exists.
- Messenger availability can be checked without consuming one-time pre-keys.
- Sending still uses the consuming pre-key bundle endpoint.
- A handle-to-DID change is detected and blocks silent sending.
- Relay tests prove device availability does not reserve pre-keys.
- App tests prove contact picker starts a thread by contact.
