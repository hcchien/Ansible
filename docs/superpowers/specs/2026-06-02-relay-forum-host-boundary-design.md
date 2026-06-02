# Relay And Forum Host Boundary Design Spec

> Status: Design
> Date: 2026-06-02
> Scope: Elix Relay, Forum Host, app, distribution frontend, discovery,
> authorization, storage ownership, and deployment boundaries

## Summary

Tris-Aura should treat Elix Relay and Forum Host as separate product and
engineering roles, even when the first implementation runs both roles inside the
same Phoenix service.

Elix Relay is identity, session, discovery, sync, and federation
infrastructure. Forum Host is the canonical owner of forum state: hosted boards,
threads, posts, board rules, permissions, moderation, and host announcements.
The app is the user-key holder and local projection store. The distribution
frontend is a scoped client that writes only through a user-approved web
session.

The immediate implementation may keep `/api/v1/forum-host/*` inside
`ansible_relay/phoenix`, but the API contract must stop depending on that
co-location. Forum Host writes must be accepted only after either direct app DID
signature verification or verification of a short-lived Relay-issued web
session scoped to the target Forum Host.

## Constitution Review

This design touches identity, storage, sync, verification, Relay, Forum Host,
AppView, moderation, and community governance. The engineering constitution
applies.

- User-controlled identity: app-originated writes use the user's DID signing
  key. The Forum Host never receives or stores user private keys.
- Data leaving the device: only user-chosen public or unlisted forum write
  intents, selected discovery requests, and selected subscription state leave
  the app. Private content remains fail-closed.
- Minimum claim: Forum Host write authorization needs DID, target host, target
  board, action scope, trust tier where relevant, expiry, and signature or
  session proof. It does not need raw legal identity.
- Raw identity exclusion: raw legal identity fields, provider assertions,
  personhood nullifiers, biometrics, and private keys must not appear in Relay
  payloads, Forum Host payloads, discovery payloads, logs, or federation
  payloads.
- Trust and moderation: trust tier is an input to host policy and rate limits,
  not a substitute for host authorization. Moderation and rate-limit outcomes
  must be reason-coded.
- Personhood binding: this design does not create a new personhood binding or
  duplicate-prevention key.
- Exit and portability: users can choose a different Forum Host, unsubscribe
  from hosted boards, and preserve local projections as non-canonical cached
  records.
- External host compliance: Forum Host discovery must expose
  `constitution_compliance`; unknown external hosts default to `unknown` before
  first-party ranking, recommendation, trust, or sync policy relies on them.

No constitution conflict is intended. This design reduces the current ambiguity
where a Relay route can appear to be the sole authority for forum identity.

## Current State

As of the 2026-06-02 implementation pass, the repo has a co-located Elix Relay
and Forum Host MVP under `ansible_relay/phoenix`:

- `GET /api/v1/discovery`
- `GET /api/v1/forum-host`
- `GET /api/v1/forum-host/boards`
- `POST /api/v1/forum-host/boards`
- `POST /api/v1/forum-host/web/threads`

Relay discovery returns Relay metadata, announcements, featured Forum Hosts,
featured boards, cache/version fields, and visible `constitution_compliance`.
Forum Host metadata now exposes compliance, capabilities, host identity,
accepted session issuers, rules, posting policy, and moderation policy. Hosted
board discovery reads the Forum Host store seed/catalog instead of only a
controller-local hard-coded fixture.

The app has `ForumHostClient.getHostInfo()`,
`ForumHostClient.listHostedBoards()`, and `ForumHostClient.createHostedBoard()`.
The app create-board path sends a DID signed intent with `target_forum_host`;
it is not web-session gated. Web-originated Forum Host writes use scoped Relay
web sessions with the target Forum Host audience.

The browser transport mismatch has been resolved. Challenge creation is
unauthenticated, approved challenge polling runs with same-origin credentials so
the browser accepts the relay's httpOnly `trisaura_session` cookie, and scoped
web APIs use that cookie. Bearer session tokens remain a compatibility path for
non-browser callers, but the frontend does not store or send bearer tokens.

The app first-run surface now loads Relay discovery only when no active Elix
Relay/Forum Host and no hosted-board projection/subscription exists. It displays
Relay announcements, starter boards, and compliance labels, but it does not
auto-subscribe, auto-post, or create local boards.

## Approaches Considered

### Approach A: Co-located MVP With Explicit Boundaries

Keep the current Phoenix service as the first implementation host for both Elix
Relay and Forum Host routes, but make the contracts independent. Use separate
controllers, separate storage tables, explicit role metadata, and authorization
that would still work if Forum Host moved to another Cloud Run service.

This is the recommended approach. It lowers immediate deployment cost while
preventing the API contract from assuming Relay and Forum Host are the same
authority.

### Approach B: Fully Separate Relay And Forum Host Now

Split Relay and Forum Host into separate services and databases immediately.
This is architecturally clean, but it expands implementation scope across
deployment, auth, service discovery, CORS, migrations, and operational
monitoring before the contract has stabilized.

This can be the later deployment shape, not the first corrective step.

### Approach C: Relay As Canonical Forum Owner

Treat Relay as the single source of truth for hosted boards, posts, moderation,
and discovery. This is rejected. It conflicts with the existing Forum Host
ownership model, blurs community governance, and makes Relay look like the
universal forum authority.

## Target Architecture

```text
Remote Config
  -> default_elix_relay_url

Elix Relay DB/API
  -> DID public-key cache and reputation inputs
  -> web-session challenge, approval, expiry, revocation
  -> app-facing discovery catalog
  -> Relay announcements and service status
  -> sync, federation, messenger, and publication infrastructure

Forum Host DB/API
  -> host identity and host signing key metadata
  -> hosted boards, threads, posts
  -> board rules, permissions, moderation policy
  -> accepted write intents and idempotency records
  -> host and board announcements
  -> moderation logs and reason-coded enforcement events

App
  -> user DID key holder
  -> local projections, subscriptions, drafts, write intents
  -> direct signed-intent client for Forum Host writes

Distribution Frontend
  -> no user private key
  -> scoped web-session client
  -> reads public Forum Host data
  -> writes only with an approved scoped session
```

Forum Host is not a local app clone. The local app acts for the user because it
holds the user's DID key. Forum Host acts as a server authority for hosted forum
state. It needs a server identity, but not a user identity.

## Discovery Model

Discovery has two layers.

### Elix Relay Discovery

Elix Relay should expose an app-facing discovery endpoint, for example
`GET /api/v1/discovery`. This endpoint answers: "How can a first-time app user
start?"

The response should include:

- Relay identity, version, status, and capabilities.
- Relay announcements such as service maintenance or security notices.
- Featured or default Forum Hosts.
- Featured starter boards by canonical URI.
- Locale-aware labels and descriptions when available.
- Discovery document version and cache policy.

Elix Relay discovery is an index and curation layer. It is not the canonical
source of Forum Host board state. A featured board entry should point to a
Forum Host and canonical board URI; the app should resolve current host metadata
and board metadata from the Forum Host before subscribing.

Relay discovery can be configured by deployment config and refreshed from
Forum Host discovery, but it must not silently overwrite Forum Host rules or
moderation state.

### Forum Host Discovery

Forum Host should expose host-owned discovery:

- `GET /api/v1/forum-host`
- `GET /api/v1/forum-host/boards`
- `GET /api/v1/forum-host/announcements`

The host metadata response should include:

- `forum_host_id`
- `display_name`
- `canonical_base_url`
- `server_kind`
- `capabilities`
- `constitution_compliance`
- `host_public_keys` or a JWKS URL
- `accepted_session_issuers` or issuer discovery URL
- visible host rules and policy summary
- moderation policy summary
- posting trust requirements

The board response should include:

- stable hosted board id
- canonical board URI
- title and description
- language and tags when known
- read/write permissions visible to the caller
- posting policy summary
- moderation policy summary or inherited host policy
- board announcement references when present

Forum Host discovery answers: "What does this host actually provide, and what
rules apply before I post?"

## Announcements

Announcements should be split by owner.

Relay announcements are operational or security notices for the Relay service
and app bootstrap path. Examples: maintenance, default Relay migration, security
incident notice, or discovery catalog changes.

Forum Host announcements are governance or board-level notices. Examples: rule
updates, moderation policy changes, board migration, event-specific posting
limits, or host maintenance that affects hosted boards.

The app should be able to show both, but it must preserve the owner in the UI
and storage. A Relay announcement is not a Forum Host rule. A Forum Host
announcement is not a global network policy.

## Forum Host Server Identity

Forum Host needs a server identity so apps, Relays, and other hosts can verify
that host metadata and accepted forum records came from the claimed host.

The first implementation can use:

- `forum_host_id`
- `canonical_base_url`
- `host_key_id`
- an Ed25519 public key or JWKS document
- a signed host metadata document

A future implementation may represent the host as `did:web` or another
server-controlled DID. This identity is a server identity only. It must not be
used as a user identity and must not sign user-authored content as if it came
from the user.

Forum Host should use its key to sign accepted records or acceptance receipts
where clients need tamper evidence:

- accepted hosted board creation
- accepted thread creation
- accepted post or reply creation
- tombstone or moderation events
- host metadata snapshots

## Authorization Model

Forum Host write APIs must fail closed. They support two first-class
authorization modes.

### App-Originated Signed Intent

The app signs a write intent with the user's DID key and sends it directly to
the selected Forum Host.

The signed intent should include:

- `type`
- `version`
- `intent_id`
- `author_did`
- `target_forum_host`
- target board or requested board metadata
- action, such as `create_board`, `create_thread`, `reply`, `edit`, or
  `delete`
- payload or payload hash
- `created_at`
- `expires_at`
- nonce or idempotency key
- signature

The Forum Host must verify:

- the signature against the user's DID public key;
- the intent has not expired;
- the target host/audience matches this Forum Host;
- the intent id has not already been accepted with different content;
- the requested action is allowed by host and board policy;
- the user meets relevant trust-tier, rate-limit, and moderation requirements.

Relay may help resolve a DID public key or trust tier, but Forum Host must not
blindly trust an unsigned Relay-forwarded `author_did` or signature-verification
result. If Relay provides a verification or reputation assertion, that
assertion must be signed, scoped, time-limited, and audienced to the Forum Host.

### Web-Originated Session Write

The distribution frontend does not hold the user's DID private key. It uses an
app-mediated web session.

The preferred model is:

1. Web requests a Relay web-session challenge with requested scopes.
2. App displays web origin, Relay origin, target scopes, expiry, and DID.
3. App signs the grant.
4. Relay verifies the grant and issues a short-lived session.
5. In the current co-located MVP, Relay installs an httpOnly
   `trisaura_session` cookie and Forum Host web APIs verify that session through
   the Relay web-session store with required scope and audience checks.
6. For a later split-service deployment, Forum Host can replace same-process
   lookup with Relay introspection or an offline-verifiable signed session
   artifact.

The split-service session artifact or introspection result should include:

- issuer `iss`
- audience `aud`, bound to the target Forum Host
- subject `sub`, the user DID
- scopes
- trust tier
- web origin
- approving device id
- issued-at time
- expiry
- token id `jti`

Forum Host must verify:

- issuer is an allowed Relay or session issuer;
- issuer key is current and trusted by host config;
- audience matches this Forum Host;
- token is unexpired;
- required scope is present;
- trust tier is treated only as a policy input;
- host and board permissions allow the requested action.

An opaque-token introspection model may be used only as a transitional mode. If
used, Forum Host must call a Relay introspection endpoint over authenticated
server-to-server transport and must fail closed when introspection is
unavailable. The offline-verifiable model is preferred because it lets Forum
Host remain independently deployable.

### Hosted Web Accounts

Hosted web accounts are a lower-trust path owned by the Forum Host. They are
not the same as app-approved self-custody DID sessions. If implemented, Forum
Host must label their trust tier distinctly and apply separate rate limits and
moderation policy.

## Read Authorization

Public discovery and public board reads are available without a session unless
the Forum Host marks the host, board, or content as restricted.

Restricted reads require either:

- a web session with `forum:read` and host permission; or
- an app request authorized according to host policy; or
- a hosted web account session when that path exists.

Read authorization must not leak private board existence or private content
through error messages, discovery listings, logs, or Relay catalog entries.

## Storage Ownership

Relay and Forum Host should have separate data ownership even if their first
deployment uses one Phoenix app.

Relay-owned storage:

- DID public-key cache and identity anchors
- reputation and trust-tier inputs
- web-session challenges and issued sessions
- discovery catalog entries
- Relay announcements
- publication intents and federation adapter state
- messenger relay state

Forum Host-owned storage:

- host metadata and host keys
- allowed session issuers
- hosted boards
- hosted threads and posts
- board subscriptions when the host owns subscription state
- accepted intents and idempotency records
- moderation actions and reason codes
- host and board announcements
- tombstones and deletion policy records

App-owned storage:

- local projections of hosted boards, threads, and posts
- board subscriptions as user-local sync preferences
- drafts and queued write intents
- local-only personal content
- user DID private key material in the appropriate secure storage mode

## Deployment And Compatibility

The first implementation can stay co-located:

```text
single Phoenix service
  /api/v1/discovery              Elix Relay role
  /api/v1/web-sessions/*         Elix Relay role
  /api/v1/forum-host/*           Forum Host role
  separate modules and storage ownership
```

This preserves current local development and Cloud Run simplicity. The contract
must still expose role boundaries through metadata and auth:

- Relay discovery returns Forum Host URLs, even when they are the same origin.
- Forum Host metadata returns its own identity, compliance level, capabilities,
  rules, and accepted session issuers.
- App settings may show "Elix Relay" for the user-facing bootstrap endpoint,
  but the selected hosted board projection must preserve the owning
  `forumHostId` and canonical board URI.

The later deployment can split services:

```text
Elix Relay Cloud Run + Relay DB
Forum Host Cloud Run + Forum Host DB
```

No app behavior should require those services to remain co-located.

## First-Run App Flow

1. App reads the default Elix Relay URL from `AppEnvironment.defaultRelayBaseUrl`
   in the current MVP. Remote Config can feed the same value later.
2. App calls `GET /api/v1/discovery` on the Elix Relay.
3. App displays Relay announcements and starter Forum Host or board options.
4. When the user chooses a starter board action, the app opens Sync settings or
   the Add Elix Relay flow with the discovered `forumHostUrl`.
5. The current first-run action does not auto-subscribe, auto-post, or create a
   local board. Explicit hosted-board creation/subscription flows create local
   projections only after the user chooses that action.
6. App displays host/board compliance level before relying on discovery output.
7. Forum writes remain explicit signed intents to the selected Forum Host.

If Remote Config or Relay discovery is unavailable, the app should preserve
local-first behavior and show a setup state instead of silently publishing.

## Error Handling

Forum Host write APIs must return explicit errors:

- `401 invalid_signature` or `invalid_session`
- `403 missing_required_scope`
- `403 audience_mismatch`
- `403 host_policy_denied`
- `409 duplicate_intent`
- `410 board_tombstoned`
- `422 invalid_intent`
- `429 rate_limited`

Moderation and rate-limit responses must include a reason code when safe. They
must not include raw identity fields or private verifier data.

Discovery errors should distinguish:

- Relay discovery unavailable
- Forum Host metadata unavailable
- host compliance unknown
- board no longer exists
- board restricted

The app should not auto-subscribe or auto-post when any required discovery,
signature, token, compliance, or host-policy check fails.

## Testing Requirements

Relay tests:

- `GET /api/v1/discovery` returns Relay metadata, announcements, featured
  Forum Hosts, featured boards, and cache/version fields.
- Relay discovery entries do not become canonical Forum Host rules.
- Relay web sessions include host audience, scopes, expiry, trust tier,
  and subject DID.

Forum Host tests:

- `GET /api/v1/forum-host` includes `constitution_compliance`, host identity,
  capabilities, rules, and accepted session issuers.
- `GET /api/v1/forum-host/boards` returns durable seeded boards rather than
  only a hard-coded controller fixture.
- App signed-intent write succeeds when DID signature, audience, expiry, and
  host policy are valid.
- App signed-intent write fails when signature, audience, expiry, or
  idempotency check fails.
- Web session write succeeds with a valid Relay-issued token and required
  scope.
- Web session write fails with missing scope, invalid issuer, wrong audience,
  expired token, or unavailable introspection in transitional mode.
- Forum Host does not accept unsigned Relay-forwarded `author_did` as proof.

App tests:

- First-run discovery uses the configured default Elix Relay URL. Current MVP
  code reads `AppEnvironment.defaultRelayBaseUrl`; Remote Config remains a
  future provider for that value.
- Starter board selection resolves Forum Host metadata before subscription.
- Host compliance level is stored or displayed before relying on host behavior.
- App create-board and thread creation use signed-intent auth, not web-session
  auth.
- Private content is not sent through discovery, Relay catalog, or Forum Host
  write paths.

Distribution frontend tests:

- Browser-auth transport matches server verification through the httpOnly
  cookie path; bearer remains only a compatibility path for non-browser callers.
- Missing scope disables or rejects post/reply actions.
- Web client never stores DID private keys.

Security and constitution tests:

- Discovery and write payloads exclude raw legal identity fields, provider
  assertions, private keys, biometric data, and personhood commitments.
- Unknown external Forum Hosts default to `constitution_compliance: "unknown"`.
- Rate-limit and moderation responses include reason codes where safe.

## Implementation Order

1. Add or update specs and implementation plan for this boundary.
2. Add Forum Host discovery fields: compliance level, host identity, rules,
   capabilities, and accepted session issuers.
3. Add Elix Relay discovery with Relay announcements and starter host/board
   catalog.
4. Split Forum Host write auth into app signed-intent verification and web
   session verification.
5. Keep browser cookie transport and server verification aligned.
6. Replace hard-coded hosted board discovery with durable seeded Forum Host
   boards.
7. Add app first-run discovery and announcement UI.
8. Prepare service split by keeping Relay and Forum Host storage and modules
   separately owned even when co-located.

## Acceptance Criteria

- The codebase has an explicit Relay discovery endpoint for app bootstrap.
- Forum Host discovery exposes host identity, rules, capabilities, and
  `constitution_compliance`.
- Forum Host writes are never accepted from an unsigned `author_did`.
- App-originated writes use DID signed intents.
- Web-originated writes use scoped Relay-issued sessions audienced to the Forum
  Host.
- App can onboard a first-time user from the configured default Elix Relay to
  starter boards without requiring manual Forum Host setup. The current MVP uses
  `AppEnvironment.defaultRelayBaseUrl`; Remote Config can supply that value
  later.
- Relay announcements and Forum Host announcements are separately represented.
- Current co-located Phoenix deployment remains possible, but APIs no longer
  require Relay and Forum Host to be the same authority.
