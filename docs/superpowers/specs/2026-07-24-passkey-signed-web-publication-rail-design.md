# Passkey-Signed Web Publication Rail Design

> Status: Proposed
> Date: 2026-07-24
> Scope: Distribution frontend, WebAuthn/passkeys, app-mediated web sessions,
> user identity writes, Relay sync, Forum Host records, AppView ingestion, and
> federation publication

## Summary

Every first-party web identity write must carry fresh, content-bound evidence
of user presence from a P-256 WebAuthn credential authorized by the user's DID.
A web-session cookie identifies the browser and limits its scopes, but it is
not sufficient authority to create, edit, or delete user-authored content.

For each write, the browser prepares one canonical operation, obtains a
single-use Relay challenge bound to that operation hash, and asks the user to
approve a WebAuthn assertion. The Relay and Forum Host verify the session,
assertion, DID-to-credential authorization, target policy, and replay state
before accepting the operation.

The exact accepted operation and author-proof envelope are reused for Forum
Host persistence, Relay sync, AppView ingestion, and any user-selected
federation publication. No Relay, Forum Host, frontend server, or AppView may
replace the user's proof with a server-generated user signature.

This deliberately introduces visible friction. The product promise is stronger
than possession of a session cookie: a signed post means a user-controlled,
hardware-backed credential approved that exact operation.

## Constitution Review

This feature touches identity, storage, sync, verification, federation,
moderation, community governance, Relay, Forum Host, and AppView behavior. The
engineering constitution applies.

1. **User-controlled identity or credential**
   - The author uses a P-256 WebAuthn credential enrolled to an anchored DID.
   - Enrollment is authorized by the user's existing P-256 identity key.
   - The WebAuthn private key remains non-exportable in platform or roaming
     authenticator hardware.
   - A web-session cookie is not treated as a signing key or identity proof.

2. **Data leaving the device**
   - Only the user-selected canonical operation, its hash, public credential
     identifier, WebAuthn assertion, required session binding, and declared
     publication metadata leave the browser.
   - Private content must not use this public Forum Host/publication rail.
   - Unlisted and federated visibility remain explicit user choices.

3. **Minimum claim**
   - Content authorization needs only the author DID, authorized credential,
     operation hash, target, action, timestamps, nonce, and WebAuthn proof.
   - Credential-gated boards separately receive only the minimum board-access
     presentation required by their policy.

4. **Raw identity exclusion**
   - Raw legal identity, provider assertions, biometrics, private keys,
     personhood commitments, full VCs, and authenticator attestation identity
     must not appear in operations, logs, AppView records, or federation
     payloads.
   - WebAuthn user verification is a local authenticator result. It is not a
     legal-identity assertion.

5. **Trust, rate limits, access, and moderation**
   - Passkey approval proves control and consent, not verified-human status.
   - Trust tier and board credentials remain separate policy inputs.
   - Policy, moderation, lock, replay, and rate-limit rejections are
     reason-coded.

6. **Personhood binding**
   - This design creates no personhood binding or duplicate-prevention key.
   - It must not derive trust-tier upgrades from passkey usage alone.

7. **Exit, revocation, rotation, and lower-trust paths**
   - Users can revoke an enrolled web credential and active web sessions.
   - Credential rotation preserves verification of historical proofs.
   - Anonymous reading and lower-trust hosted accounts may remain available
     where host policy permits, but they must not be labeled as self-custody
     DID writes.

8. **External hosts**
   - First-party hosts must implement this full verification contract.
   - External host compliance remains discoverable. A host that accepts only a
     cookie or substitutes a host signature for the author proof cannot claim
     `constitution_compliant`.

### Constitution Conflict Resolution

The older
`2026-05-11-app-mediated-web-session-design.md` permits a scoped app-approved
session to create web posts without a content-level author signature. The
newer `2026-07-24-p256-identity-write-policy.md` requires all new first-party
identity writes to use hardware-backed P-256 authorization.

This spec supersedes the older session-only write authorization:

- app-mediated sessions continue to provide authentication, audience, expiry,
  and scope;
- every identity write additionally requires a fresh content-bound WebAuthn
  assertion;
- session-only web write endpoints are transitional and must not persist
  canonical user-authored records.

The P-256 identity-write policy must recognize
`webauthn-p256-sha256` as a hardware-backed P-256 author-proof scheme when the
credential is validly delegated by the DID. It is not a downgrade to a hosted
or exportable key.

## Goals

- Require explicit user presence for every web post, reply, edit, delete, and
  identity-attributed reaction.
- Bind the WebAuthn assertion to the exact canonical operation.
- Preserve one author-verifiable operation across Forum Host, sync, AppView,
  and federation boundaries.
- Keep root DID private keys out of the browser.
- Preserve offline-safe idempotent retries after the assertion has been
  created.
- Keep board eligibility proof separate from author consent.
- Fail closed when session, challenge, proof, DID delegation, board capability,
  or visibility validation is unavailable.

## Non-Goals

- Exporting the app's root DID private key to the browser.
- Treating a passkey as verified-human or legal-identity evidence.
- Allowing a session cookie to authorize an identity write by itself.
- Long-lived unattended browser posting.
- Background bots or scheduled publication under a user's DID.
- Private-board plaintext publication through the public web frontend.
- Making WebAuthn attestation vendor or device identity public.
- Replacing Forum Host governance, moderation, or board credential policy.

## Product Principle

The confirmation ceremony must communicate:

> You are signing this exact action as your DID.

Before invoking the authenticator, the frontend must show:

- action: publish, reply, edit, delete, or react;
- target Forum Host and board;
- content title or a local content summary;
- visibility and whether federation is requested;
- any board eligibility requirement already satisfied or still required.

The frontend must not use misleading copy such as "confirm login" for a content
write. Browser password-manager or platform Passkey UI remains
platform-controlled, but the first-party confirmation surface must explain the
operation before that UI appears.

## Current State And Gap

### Existing Web Session

The current app-mediated session flow correctly:

- keeps the root DID key in the app;
- signs a canonical session grant;
- binds origin, audience, scopes, DID, approving device, and expiry;
- installs an httpOnly cookie;
- supports expiry and revocation.

It authenticates a browser but does not prove user approval of each write.

### Existing Web Thread Endpoint

`POST /api/v1/forum-host/web/threads` currently:

- requires a `forum:post` web-session scope;
- checks DID-level rate limits;
- checks posting tier, board capability, and thread lock state;
- returns `202 accepted`.

It currently does not:

- receive a canonical content operation;
- receive or verify a content-bound Passkey assertion;
- persist a Forum Host thread;
- append a signed Relay op;
- create a publication intent;
- provide independently verifiable author provenance.

This endpoint is a transport and policy smoke path, not a production
publication path.

### Existing WebAuthn Sync Capability

The existing WebAuthn sync ceremony verifies user presence against a random
challenge and issues a five-minute `sync:write` bearer capability. That proves
recent authentication, but the assertion is not bound to an exact content
operation. A bearer capability must not be promoted into author consent.

The credential enrollment and sign-counter logic can be reused. The generic
capability exchange remains useful for non-identity sync operations, but it
does not satisfy this spec for authored writes.

### Existing Ops And Publication Validation

Relay ops and publication intents currently require a P-256 DID signature over
their signing payloads. The new web proof must be accepted only through an
explicit `webauthn-p256-sha256` verification path that resolves:

```text
anchored DID
  -> DID-signed WebAuthn credential delegation
  -> WebAuthn assertion over a challenge bound to canonical operation hash
  -> exact accepted operation
```

## Trust And Key Model

### Root Identity Key

The user's anchored P-256 identity key remains the root authority. It is held
by the app or another constitution-compliant secure-hardware identity client.

### WebAuthn Credential

A web credential is:

- P-256 / ES256;
- resident or discoverable where supported;
- configured with `userVerification: "required"`;
- scoped to the first-party RP ID;
- enrolled only after a DID-key signature authorizes the credential;
- revocable without rotating the root DID;
- not automatically a personhood or trust-tier upgrade.

### Credential Delegation Record

Enrollment must create a durable, signed delegation:

```json
{
  "type": "io.trisaura.identity.webCredentialDelegation",
  "version": 1,
  "delegation_id": "wcd_01...",
  "subject_did": "did:...",
  "credential_id_hash": "sha256:...",
  "credential_public_key_thumbprint": "base64url...",
  "rp_id": "forum.elix.cool",
  "allowed_actions": [
    "forum.publish",
    "forum.reply",
    "forum.edit",
    "forum.delete",
    "forum.react"
  ],
  "created_at": "2026-07-24T08:00:00Z",
  "expires_at": null
}
```

The root identity key signs the canonical delegation. The durable verifier
record stores the public credential key, DID, RP ID, allowed actions, root
signature, creation time, revocation state, and sign counter.

The raw credential ID should be returned only where required by WebAuthn
ceremonies. Logs and cross-service audit references use a one-way credential
ID hash or public-key thumbprint.

### Revocation And Historical Verification

Revocation prevents future writes but does not invalidate proofs accepted
before `revoked_at`. Historical verification uses the credential key and
delegation state effective at the operation's accepted time.

Deleting an account may remove online lookup records according to retention
policy, but tamper-evident public records must retain enough non-sensitive
proof material to explain previously accepted authorship. Retention must not
include private keys or authenticator attestation identity.

## Canonical Web Publication Operation

All web authoring actions use a common envelope:

```json
{
  "type": "io.trisaura.webPublicationOperation",
  "version": 1,
  "operation_id": "wop_01...",
  "author_did": "did:...",
  "action": "forum.publish",
  "target_forum_host": "https://forum.elix.cool",
  "board_id": "board_...",
  "entity_type": "thread",
  "entity_id": "thread_...",
  "parent_id": null,
  "visibility": "public",
  "federate": true,
  "payload": {
    "title": "Example",
    "body": "Example body"
  },
  "payload_hash": "sha256-lowercase-hex",
  "board_policy_version": 3,
  "created_at": "2026-07-24T08:30:00Z",
  "expires_at": "2026-07-24T08:35:00Z",
  "nonce": "base64url-random"
}
```

### Canonicalization

- Use the repository's canonical JSON algorithm: object keys sorted
  lexicographically, arrays order-preserving, UTF-8, and no insignificant
  whitespace.
- `payload_hash` is lowercase SHA-256 hex of canonical `payload`.
- `operation_hash` is lowercase SHA-256 hex of the complete canonical
  operation.
- The operation must contain no signature or proof while computing
  `operation_hash`.
- All services must share fixture vectors for canonical bytes and hashes.

### Operation Semantics

- `operation_id` is globally unique and is the idempotency key.
- `entity_id` is client-generated so retries retain identity.
- `author_did`, target host, board, action, payload hash, visibility,
  federation choice, policy version, expiry, and nonce are signed indirectly
  through the challenge binding.
- `expires_at` is required and no more than five minutes after `created_at`.
- A retry after acceptance returns the same receipt if the operation hash is
  identical.
- Reusing an `operation_id` with different canonical bytes fails with
  `operation_id_conflict`.
- Edits and deletes name the target entity and expected previous revision
  hash.
- Replies name both board and parent thread.
- Reactions are identity writes when publicly attributed and require the same
  ceremony. Anonymous/local-only UI preferences do not.

### Visibility

- `private` is rejected by this rail.
- `unlisted` is not private and must be labeled accordingly.
- `federate: true` is a separate explicit choice and is permitted only for
  compatible visibility and host policy.
- The WebAuthn confirmation summary must show the visibility and federation
  choice because both are covered by the operation hash.

## Content-Bound WebAuthn Ceremony

### 1. Prepare And Review Operation

The browser validates the draft locally, generates IDs and nonce, canonicalizes
the operation, and computes `payload_hash` and `operation_hash`.

The browser must retain the exact canonical operation until completion. It
must not rewrite content, timestamps, visibility, target, or policy version
after requesting the challenge.

The frontend shows the complete local review at this point, before transmitting
the operation to request a challenge. Requesting the challenge occurs only
after the user chooses `Sign and publish` (or the equivalent action). This
choice is explicit consent to send the reviewed draft to the target Forum Host
for policy validation and signing.

### 2. Request Challenge

```http
POST /api/v1/web-publication/challenges
Cookie: trisaura_session=...
Content-Type: application/json
```

```json
{
  "operation": { "...": "..." },
  "operation_hash": "..."
}
```

The Relay verifies:

- valid app-approved session;
- subject DID equals `operation.author_did`;
- required session scope for the action;
- audience and web origin;
- operation schema, hash, target, expiry, and visibility;
- Forum Host and board existence;
- current board policy version;
- no existing conflicting operation ID;
- at least one active delegated WebAuthn credential for the action.

It stores a short-lived challenge row containing:

- challenge ID;
- random server nonce;
- subject DID;
- session `jti`;
- web origin and RP ID;
- target Forum Host;
- operation hash and operation ID;
- action and required scope;
- allowed credential IDs;
- expiry and consumed state.

The WebAuthn challenge bytes are domain-separated:

```text
SHA-256(
  "io.trisaura.web-publication.challenge.v1" ||
  0x00 || server_nonce ||
  0x00 || operation_hash_bytes ||
  0x00 || session_jti ||
  0x00 || challenge_id
)
```

The response includes standard `PublicKeyCredentialRequestOptions`:

- `challenge`;
- `rpId`;
- `allowCredentials`;
- `userVerification: "required"`;
- timeout no longer than 120 seconds.

### 3. User Approves With Passkey

The frontend keeps the reviewed operation visible or immediately recoverable
while calling `navigator.credentials.get()`. It must not introduce any changed
content or distribution choice between local review and the authenticator
ceremony.

Every operation requires a new WebAuthn ceremony. A recent assertion or bearer
capability cannot authorize a later operation.

Browser/platform conditional mediation may improve credential selection, but
it must not suppress explicit user verification or content review.

### 4. Submit Assertion

```http
POST /api/v1/web-publication/operations
Cookie: trisaura_session=...
Content-Type: application/json
```

```json
{
  "challenge_id": "wpc_01...",
  "operation": { "...": "..." },
  "operation_hash": "...",
  "credential": {
    "id": "...",
    "rawId": "...",
    "type": "public-key",
    "response": {
      "clientDataJSON": "...",
      "authenticatorData": "...",
      "signature": "...",
      "userHandle": "..."
    }
  }
}
```

### 5. Verify

The verification boundary must:

1. Load and atomically consume the challenge.
2. Recompute canonical operation bytes and both hashes.
3. Require byte-for-byte operation/hash equality with the challenge.
4. Revalidate session subject, scope, audience, origin, and expiry.
5. Resolve the credential delegation for the operation DID and action.
6. Verify WebAuthn origin, RP ID hash, challenge, credential signature, user
   presence, and user verification.
7. Enforce credential sign-counter replay rules where supported.
8. Revalidate operation expiry, board policy version, board capability, trust
   tier, rate limits, moderation state, and thread lock.
9. Atomically reserve `operation_id`.
10. Persist the canonical operation and proof envelope.

The challenge is single-use even after a failed assertion. A retry caused by a
transport failure after successful acceptance uses `operation_id` to retrieve
the existing receipt; it does not invoke Passkey again.

## Author Proof Envelope

The accepted record stores:

```json
{
  "scheme": "webauthn-p256-sha256",
  "delegation_id": "wcd_01...",
  "credential_public_key_thumbprint": "...",
  "challenge_id": "wpc_01...",
  "operation_hash": "...",
  "client_data_json": "base64url...",
  "authenticator_data": "base64url...",
  "signature": "base64url...",
  "verified_origin": "https://forum.elix.cool",
  "verified_rp_id": "forum.elix.cool",
  "user_present": true,
  "user_verified": true,
  "verified_at": "2026-07-24T08:30:04Z"
}
```

The envelope excludes:

- attestation certificate chains after enrollment validation;
- authenticator model/vendor identity unless strictly required for security;
- raw biometric or local unlock data;
- session cookie or bearer token;
- IP address;
- full VC or board presentation.

The accepted public provenance may expose the scheme, DID, operation hash,
credential thumbprint, and verification time. Raw WebAuthn assertion components
should be available only where independent verification requires them and
subject to a documented retention policy.

## Board Credential And Capability Composition

Passkey proof answers:

> Did an authorized hardware credential approve this exact operation?

Board presentation answers:

> Does the author satisfy this board's eligibility policy?

These proofs must remain separate.

For a credential-gated board:

1. Web starts the board OID4VP flow.
2. App/Wallet presents only the minimum claim.
3. Forum Host issues a short-lived board capability bound to the web
   credential public-key thumbprint.
4. The browser prepares the publication operation.
5. The Passkey signs the content-bound WebAuthn challenge.
6. Submission includes the board capability and its device-bound proof.

The Forum Host verifies both at the same acceptance boundary. Passing one does
not bypass the other. The full VC must never be copied into the publication
operation or author proof.

## Accepted Write And Distribution Pipeline

### Single Acceptance Record

The Forum Host creates one immutable acceptance record:

```text
operation
+ author proof
+ board authorization result
+ moderation/rate-limit decision
+ Forum Host acceptance receipt
```

The Forum Host signs an acceptance receipt with its server key. The host
signature proves host acceptance; it does not replace or impersonate the user
author proof.

### Forum Host Persistence

The accepted operation is projected into canonical thread, post, reaction, or
revision tables. The immutable operation and author proof remain available for
audit and re-projection.

### Relay Sync

The Relay sync log accepts `signature_scheme:
"webauthn-p256-sha256"` plus the author-proof envelope. It verifies or consumes
a Forum Host acceptance receipt according to the deployment boundary.

The sync op must retain:

- the same `operation_id`;
- the same author DID, entity IDs, action, payload, and operation hash;
- the same author proof;
- the Forum Host receipt.

No service creates a second semantic operation with a different timestamp or
payload.

### AppView

AppView ingests the accepted record or verified Relay op. It must preserve:

- author DID;
- Forum Host and board;
- operation ID and hash;
- author-proof scheme and verification status;
- moderation/tombstone state;
- provenance needed for display.

AppView may index or denormalize content, but it must not claim authorship based
only on a Relay or Forum Host signature.

### Federation

Federation occurs only when the signed operation selected an eligible
visibility and `federate: true`.

The federation adapter may translate the content into an external protocol
format. It must retain an internal mapping to the accepted operation and must
not silently broaden visibility. External protocols that cannot carry the full
author proof should expose a verifiable provenance link or host-signed
attestation that points back to the accepted record; the UI must distinguish
native author proof from translated federation provenance.

## API Surface

### Credential Enrollment

- `POST /api/v2/webauthn/register/options`
- `POST /api/v2/webauthn/register/finish`
- `GET /api/v2/webauthn/credentials`
- `POST /api/v2/webauthn/credentials/:id/revoke`

Registration finish must persist the DID-signed delegation described above.

### Publication Ceremony

- `POST /api/v1/web-publication/challenges`
- `POST /api/v1/web-publication/operations`
- `GET /api/v1/web-publication/operations/:operation_id`

The GET endpoint is scoped to the submitting session/DID and exists for
idempotent transport recovery. Public content reads continue through Forum
Host/AppView APIs.

### Transitional Endpoint

`POST /api/v1/forum-host/web/threads` must be deprecated for production
identity writes.

During migration it may:

- return `409 passkey_author_proof_required` with the new challenge endpoint;
  or
- act as a compatibility wrapper only when it receives and verifies the full
  new operation and author proof.

It must not persist content from a cookie-only request.

## Authorization Matrix

| Action | Session scope | Fresh Passkey | Board capability | Host receipt |
|---|---|---:|---:|---:|
| Publish thread | `forum:post` | Required | If policy requires | Required |
| Reply | `forum:reply` | Required | If policy requires | Required |
| Edit own content | `forum:edit` | Required | Rechecked if policy requires | Required |
| Delete own content | `forum:delete` | Required | Not normally required | Required |
| Attributed reaction | `forum:react` | Required | If host policy requires | Required |
| Read public content | None | No | No | No |
| Read protected board | `forum:read` | No content signature | Required | No |
| Moderate | Separate moderator scope | Required | Moderator authorization | Required |

Moderation uses the same content-bound proof foundation but remains a distinct
reason-coded action family and audit log.

## State Machines

### Challenge

```text
issued
  -> consumed_verified
  -> consumed_rejected
  -> expired
```

There is no transition from a consumed or expired challenge back to issued.

### Operation

```text
draft_local
  -> challenge_issued
  -> user_cancelled
  -> assertion_submitted
  -> accepted
  -> projected
  -> synced
  -> indexed
  -> federated (optional)
```

Acceptance is the identity-write commit point. Projection, sync, indexing, and
federation are retryable delivery states for the same immutable accepted
operation.

## Failure And Reason Codes

Authentication and proof:

- `invalid_web_session`
- `missing_required_scope`
- `session_subject_mismatch`
- `passkey_not_enrolled`
- `passkey_author_proof_required`
- `invalid_webauthn_challenge`
- `webauthn_challenge_expired`
- `webauthn_challenge_consumed`
- `webauthn_verification_failed`
- `user_verification_required`
- `credential_not_authorized`
- `credential_revoked`
- `sign_count_replay`

Operation:

- `invalid_operation`
- `operation_hash_mismatch`
- `operation_expired`
- `operation_id_conflict`
- `duplicate_operation`
- `visibility_not_allowed`
- `private_content_not_relayable`
- `federation_not_allowed`

Board and governance:

- `board_not_found`
- `board_policy_version_conflict`
- `board_capability_required`
- `invalid_board_capability`
- `capability_expired`
- `thread_locked`
- `host_policy_denied`
- `rate_limited`

Infrastructure verification failures return retryable `503` reason codes and
must fail closed. They must not trigger identity reset, credential re-enrollment,
or duplicate publication automatically.

## Security Requirements

- Require HTTPS secure contexts in production.
- Require exact allowed origins and RP IDs; do not reflect request origins.
- Require `userVerification: "required"` for identity writes.
- Use at least 128 bits of random server nonce and browser operation nonce.
- Domain-separate challenge derivation.
- Consume challenges atomically before or during verification.
- Store operation ID and hash with a uniqueness constraint.
- Bind challenge to session `jti`, DID, origin, host, action, and operation
  hash.
- Enforce operation and challenge expiry independently.
- Validate WebAuthn sign counters without rejecting authenticators that
  legitimately report zero according to WebAuthn rules.
- Do not log assertion signatures, session cookies, board capabilities, full
  client data, content bodies, or credential IDs.
- Log one-way identifiers, reason codes, action classes, and timing needed for
  abuse and incident review.
- Apply CSP, CSRF protection, SameSite cookies, and origin validation to all
  browser endpoints.
- Never accept a frontend-server signature as user authorship.
- Never convert WebAuthn authentication alone into verified-human status.

## Privacy And Retention

- Store only proof material necessary for verification, replay prevention,
  audit, and historical provenance.
- Challenge rows expire promptly and are swept after a short operational
  window.
- Session binding data follows web-session retention.
- Credential delegation records persist until revocation plus the minimum
  period required for historical verification.
- Raw IP and raw DID must not be joined in the same application log event.
- Content body logging is prohibited.
- Board VP/VC payloads follow their own minimal-disclosure retention and are
  not embedded in author proofs.

## UX Requirements

- The compose button opens a review step before Passkey.
- Review shows exact action, host, board, content summary, visibility, and
  federation choice.
- The primary action says `Sign and publish`, `Sign and reply`, or the
  localized equivalent.
- The UI explains that the signature proves approval of this exact content.
- Cancelling Passkey returns to the draft without losing it.
- A failed or expired challenge retains the draft and offers a new ceremony.
- After assertion submission, ambiguous network failure shows `Checking
  publication status` and queries by operation ID before asking for another
  signature.
- Accepted content shows author-proof provenance without implying legal-name
  verification.
- Accessibility: the review and error states must be keyboard navigable,
  screen-reader labeled, and must not rely only on biometric terminology.

## Service Responsibilities

### Distribution Frontend

- Build and canonicalize the operation using shared fixtures.
- Show the pre-sign review.
- Invoke WebAuthn and submit the unchanged operation/assertion.
- Store drafts locally, but never private keys, session bearer tokens, board
  capabilities in persistent storage, or raw VC data.
- Recover ambiguous submissions through operation-status lookup.

### Relay

- Own app-mediated session validation and WebAuthn credential delegation.
- Issue and consume content-bound challenges.
- Verify assertions and DID delegation.
- Enforce P-256 identity-write policy and replay controls.
- Append the accepted verified op to sync infrastructure.
- Keep session authentication distinct from author proof.

### Forum Host

- Own board policy, canonical forum records, and acceptance receipts.
- Revalidate board capability, policy version, trust input, rate limits,
  moderation, and locks at acceptance.
- Persist the immutable accepted operation and projections.
- Never accept unsigned `author_did` or cookie-only authorship.

### App

- Authorize WebAuthn credential enrollment with the root DID key.
- Approve and revoke web sessions.
- Display and revoke delegated web credentials.
- Present board credentials with minimum disclosure when needed.
- Sync accepted web operations as remote/canonical projections without
  fabricating a new local signature.

### AppView

- Ingest only accepted records with verified provenance.
- Preserve author-proof status and Forum Host ownership.
- Apply moderation and provenance labels without converting local host
  decisions into global identity judgments.

## Migration

1. Add shared canonical operation fixtures and hash vectors.
2. Extend WebAuthn enrollment with durable DID-signed delegation metadata and
   revocation APIs.
3. Add content-bound challenge and operation endpoints behind a feature flag.
4. Add `webauthn-p256-sha256` to identity-write verification.
5. Add immutable Forum Host accepted-operation storage and host receipts.
6. Project accepted web operations into Forum Host threads/posts.
7. Append the same operation/proof to Relay sync.
8. Ingest verified accepted records into AppView.
9. Add explicit federation delivery from the signed operation choice.
10. Change the frontend compose/reply/edit/delete/reaction flows to require the
    ceremony.
11. Make the old cookie-only endpoint return
    `passkey_author_proof_required`.
12. Remove any production path that persists cookie-only identity writes.

No migration may rewrite historical cookie-only smoke responses into signed
content. They were not persisted and have no author proof.

## Testing Requirements

### Shared Contract Tests

- Canonical JSON and SHA-256 fixtures match in JavaScript, Dart, and Elixir.
- Every operation action has a stable test vector.
- Changing any content, target, visibility, federation flag, timestamp, nonce,
  or policy version changes the operation hash.

### WebAuthn Tests

- Valid authorized P-256 assertion succeeds.
- Wrong origin, RP ID, challenge, credential, DID, operation hash, or session
  fails.
- Missing UV fails even if UP succeeds.
- Revoked or action-out-of-scope delegation fails.
- Consumed, expired, and sign-count replay challenges fail.
- Failed assertions burn the challenge.

### Forum Host Tests

- Cookie-only requests cannot persist content.
- A valid session plus valid content-bound proof creates exactly one immutable
  accepted operation and one canonical projection.
- Duplicate identical submissions return the original receipt.
- Duplicate IDs with changed content fail.
- Board policy, capability, lock, and moderation checks happen at acceptance,
  not only at challenge issuance.
- Host receipt signs the accepted operation hash and never claims to be the
  user signature.

### Relay Sync Tests

- The same operation ID, bytes, hash, and author proof enter the sync log.
- `webauthn-p256-sha256` succeeds only for an active delegated credential at
  acceptance time.
- Server-generated signatures cannot satisfy author-proof validation.
- Infrastructure verification outage fails closed with retryable `503`.

### AppView And Federation Tests

- AppView preserves Forum Host, board, DID, operation hash, and proof scheme.
- AppView rejects or labels records without verified author provenance.
- Federation happens only when visibility and signed `federate` choice allow.
- Federation translation retains a provenance mapping and never broadens
  visibility.

### Frontend Tests

- Every identity-write action renders review before WebAuthn.
- Passkey cancellation preserves the draft.
- The exact challenged operation is submitted unchanged.
- Ambiguous network failure queries operation status before re-signing.
- No cookie-only fallback exists.
- Browser storage contains no root key, Passkey private key, bearer session
  token, full VC, or persistent board capability.

### Constitution Tests

- Raw legal identity, provider assertions, personhood commitments, private
  keys, biometric data, and full credentials are absent from operations,
  proofs, receipts, logs, sync records, AppView records, and federation
  payloads.
- Passkey usage does not upgrade trust tier.
- External hosts that do not preserve author proof cannot be labeled
  `constitution_compliant`.
- Private content fails closed.

## Observability

Metrics should include:

- challenges issued, expired, consumed, and rejected by reason;
- assertions verified or rejected by reason;
- operations accepted, duplicated, conflicted, and rejected by action;
- projection, sync, indexing, and federation delivery lag;
- credential revocations and sign-count replay detections;
- retry/status-recovery outcomes.

Metrics and logs use low-cardinality action/reason labels. They must not expose
raw DID, credential ID, content, signature, IP, board capability, or VC claims.

## Rollout Gates

Production enablement requires:

- durable WebAuthn credential and delegation storage;
- exact production RP ID/origin configuration;
- shared canonicalization fixtures passing in all three runtimes;
- credential revocation and session revocation UI;
- immutable operation/idempotency storage;
- Forum Host persistence and receipts;
- sync/AppView provenance preservation;
- no cookie-only persistence path;
- security review of challenge binding, origin/RP validation, CSRF, replay,
  and logs;
- updated compliance review.

## Acceptance Criteria

- Every first-party web post, reply, edit, delete, and attributed reaction
  requires a fresh UV WebAuthn assertion.
- The assertion is cryptographically bound to the complete canonical operation
  hash and current app-approved web session.
- The WebAuthn credential is P-256 and authorized by a durable DID-signed
  delegation.
- A session cookie alone cannot create canonical user-authored content.
- Relay, Forum Host, AppView, and federation reuse the same immutable accepted
  operation and author proof.
- Forum Host server signatures are acceptance receipts, never substitute user
  signatures.
- Board eligibility presentation and content consent remain separate proofs.
- Private content never enters the rail.
- Retries are idempotent and do not prompt for a second signature after an
  accepted operation.
- All rejection paths are reason-coded and verification outages fail closed.
- Raw identity, private keys, biometrics, full credentials, personhood
  commitments, content bodies, and session secrets are excluded from logs.
