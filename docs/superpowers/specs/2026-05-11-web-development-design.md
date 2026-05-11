# Web Development Design Spec

> Status: Draft for implementation planning  
> Date: 2026-05-11  
> Scope: Distribution frontend, web sessions, Forum Host web APIs, trust tiers,
> browser storage, and scoped web feature set

## Goal

Define the full web feature surface for the distribution frontend without
weakening the self-custody identity model.

The web UI should become a complete Forum Host client for reading, posting, and
participating in public discussion. It should not become a browser copy of the
local-first app. Browser sessions are scoped, short-lived, revocable, and never
receive the app user's root DID private key.

## Identity And Trust Model

Web features must be gated by explicit identity tier:

| Tier | Source | Web Capability Summary |
|---|---|---|
| `anonymous` | No login | Public reading only, with anti-abuse limits |
| `basic_web` | Hosted web account | Basic profile, limited posting/replies, stricter rate limits |
| `web_passkey` | Browser WebAuthn/passkey account | Same feature class as `basic_web`, stronger account continuity |
| `self_custody_did` | App-approved web session signed by DID | Full scoped Forum Host participation as the DID |
| `verified_human` | Accepted VC/reputation upgrade | Higher limits and stronger provenance label |

`self_custody_did` on web means the current browser session was approved by the
app. It does not mean the browser owns or stores the DID private key.

## Web Session Security Baseline

All logged-in web features must use relay-issued session tokens.

Rules:

- Store only relay-issued web session tokens in the browser.
- Never store DID private keys, app seed material, passkey private material, or
  delegated signing keys in browser storage for the first implementation.
- Bind `self_custody_did` sessions to app-signed grants containing
  `challenge_id`, `relay_origin`, `web_origin`, `subject_did`,
  `approving_device_id`, scopes, `created_at`, and `expires_at`.
- Treat `basic_web` and `web_passkey` accounts as separate trust tiers even if
  they can use the same posting UI.
- Expire web sessions and require re-approval when the token expires.
- Provide user-visible revocation for current and other active web sessions.
- Fail closed when scope, origin, expiry, or DID cache validation fails.

Session policy:

- The QR/deep-link approval challenge defaults to 5 minutes and is capped at 15
  minutes.
- App-approved web sessions default to 12 hours.
- Relay rejects grants longer than 24 hours.
- Each DID can have at most 5 active app-approved web sessions.
- Each approving app device can approve at most 3 new web sessions per DID per
  rolling hour.
- Posting and reply quota is global per DID/account across all browser
  sessions, with additional per-session and network-level limits allowed.
- Challenge creation attempts are peer-rate-limited by the relay using redacted
  network metadata.
- Rate-limit logs must use `subject_type` and one-way `subject_hash` fields
  instead of raw DID/IP values.

Implementation note:

- `ansible_distribution_frontend/src/web_session_client.mjs` owns the initial
  web-session client behavior: trust-tier classification, challenge status
  handling, and browser token storage.

## Web Scoped Features

### Public Reading

Available to anonymous users unless the Forum Host marks a surface as private
or restricted:

- View public Forum Host landing page.
- Browse public hosted boards.
- View board metadata, description, rules, moderators, and provenance.
- View public threads and replies.
- View public user profiles, handles, DID/public identity labels, and trust
  tier display.
- Search or filter public boards, threads, and users when supported by the
  Forum Host.
- Open canonical board, thread, post, and profile URLs.
- View federation/provenance labels for Nostr, ActivityPub, Forum Host, and
  app-approved DID content.

### Authentication And Onboarding

Available through web UI:

- Create a `basic_web` account without requiring app installation.
- Sign in to a hosted web account.
- Add or use a browser passkey for `web_passkey` authentication.
- Start app-mediated login by creating a relay web-session challenge.
- Show QR code and deep link for app approval.
- Poll challenge status: `pending`, `approved`, `rejected`, and `expired`.
- On approval, store the relay-issued session token and mark the session as
  `self_custody_did`.
- Explain trust tier differences in account/session settings without implying
  that browser passkey equals app-held DID custody.
- Upgrade from `basic_web` or `web_passkey` to an app-approved DID session.

### Account And Session Management

Available to logged-in users, scoped by session type:

- View current account/session identity.
- View trust tier, granted scopes, session expiry, and web origin.
- Revoke the current web session.
- List and revoke active web sessions for the same account or DID when the
  relay exposes that data.
- Refresh or re-run app-mediated approval after expiry.
- Sign out and clear browser session state.
- Manage display name, avatar, bio, and profile links when permitted by tier.
- Link a hosted web account to an app-approved DID session when relay policy
  allows account upgrade.

### Forum Host Participation

Available to logged-in users with the required scopes and host permissions:

- Join or subscribe to hosted boards.
- Start a hosted board thread with `forum:post`.
- Reply to hosted board threads with `forum:reply`.
- Edit own hosted web posts when the Forum Host supports edit policy.
- Delete or tombstone own hosted web posts when allowed by host policy.
- React to posts with a low-risk interaction scope or hosted account permission.
- Follow users, boards, or threads when the Forum Host supports follow state.
- Save/bookmark boards, threads, and posts to the web account.
- Report posts, threads, boards, and users for moderation.
- View posting errors, moderation rejections, rate-limit messages, and retryable
  failures.

For `self_custody_did` sessions, writes must be attributed to the approved DID
and include `trust_tier: self_custody_did`. For `basic_web` and `web_passkey`,
writes must be attributed to the hosted web account tier.

### Content Creation UX

The web composer should support the full Forum Host write path:

- Create top-level thread drafts in the browser.
- Create replies in context.
- Preview markdown or supported rich text before posting.
- Attach content metadata supported by the Forum Host.
- Choose visibility options exposed by the Forum Host.
- Show selected identity/tier before posting.
- Show target board and host before posting.
- Prevent submit when the session lacks required scope.
- Resume draft after login when safe to do so.

The web composer must not expose local-first app-only content modes that require
local database ownership, private local storage, or app-only signing.

### Notifications And Inbox

Available when relay-side notification state exists:

- View replies to the user's posts.
- View mentions.
- View moderation notices.
- View session/security notices such as approval, expiry, and revocation.
- Mark web notifications as read.

Notifications must be relay-side web state. They must not imply access to
private app-local inbox content.

### Moderation And Safety

Available according to Forum Host permissions:

- Report content and users.
- View board rules and moderation status.
- Hide, mute, or block users at the web account/session level.
- For moderators, review reports and apply host-supported actions only if the
  session includes explicit moderator/admin scope.

Moderator and admin actions are not part of the first app-mediated web session
scope. They require separate scopes and a separate approval UI.

### Federation And Provenance Display

The web UI should make provenance inspectable:

- Show whether content is hosted locally by the Forum Host, mirrored from
  federation, or projected from an app-owned source.
- Show whether the author is `basic_web`, `web_passkey`, `self_custody_did`, or
  `verified_human`.
- Show canonical URLs for board, thread, post, and profile.
- Show remote protocol labels when content came from Nostr or ActivityPub.
- Avoid presenting lower-trust web accounts as equivalent to app-approved DID
  sessions.

## Explicitly Excluded From Web V1

The first full web implementation must not include:

- DID private key export, import, backup, or recovery.
- DID root rotation.
- High-risk identity administration.
- Local-first private notes, private murmurs, or private local collections.
- App local database sync or direct browser access to local app content.
- Long-lived delegated browser signing keys.
- Admin/moderator scopes inside the default app-mediated session.
- Unlimited session lifetime.
- Silent session approval without explicit app user confirmation.

These can be designed later as separate specs with their own threat model.

## Scope Names

Initial web session scopes:

| Scope | Meaning |
|---|---|
| `identity:display` | Read public DID/account display data for the current session |
| `forum:read` | Read session-owned web state and restricted board data allowed by host policy |
| `forum:post` | Create top-level hosted board threads |
| `forum:reply` | Create replies to hosted board threads |
| `session:revoke` | Revoke current web session and, when allowed, other sessions for same identity |
| `profile:write` | Edit relay-hosted profile fields |
| `reaction:write` | Create or remove reactions/bookmarks/follows when supported |
| `report:write` | Submit moderation reports |
| `notification:read` | Read relay-side web notifications |
| `notification:write` | Mark relay-side web notifications as read |

The default app-mediated DID approval should request the smallest scope set
needed for the current user action. For example, reading plus posting does not
need `profile:write`.

## Product Modes

The web UI should support three visible modes:

### Public Mode

No session token. The user can browse public content and start sign-in.

### Hosted Web Mode

The user has a hosted web account session. The UI enables basic participation
according to host policy, but displays a lower trust tier.

### App-Approved DID Mode

The user has a relay-issued session token backed by an app-signed DID grant. The
UI enables scoped self-custody DID participation and shows expiry/revocation
controls.

## API Expectations

The web frontend should rely on relay and Forum Host APIs:

- `POST /api/v1/web-sessions/challenges`
- `GET /api/v1/web-sessions/challenges/:id`
- `POST /api/v1/web-sessions/revoke`
- `GET /api/v1/web-sessions/me`
- `GET /api/v1/web-sessions`
- Forum Host read APIs for boards, threads, posts, profiles, and metadata.
- Forum Host write APIs protected by scoped bearer session checks.

Future implementation plans should add any missing web account, passkey,
profile, notification, reaction, report, and session-list endpoints explicitly
instead of overloading the app-mediated DID session API.

## Failure Behavior

- Challenge pending: keep polling until expiry and show QR/deep link.
- Challenge approved: store only the relay-issued `session_token`, stop
  polling, and enter `self_custody_did` mode when the relay reports that tier.
- Challenge rejected: clear token state, show retry, and keep browser
  unauthenticated.
- Challenge expired: clear token state, discard challenge, and create a new one.
- Session expired: clear token and ask user to sign in again.
- Missing scope: disable action in UI and handle relay `403`.
- Unknown token: clear token and return to public mode.
- App-approved DID no longer active: clear session and require a new approval.
- Network failure: preserve drafts locally when safe, but do not submit without
  a valid session.

## Acceptance Criteria

- Web feature list clearly distinguishes public, hosted web, passkey web, and
  app-approved DID capabilities.
- Web self-custody features require app-mediated session approval and scoped
  relay bearer tokens.
- The browser never receives or stores DID private keys.
- Forum write features are available on web through scoped Forum Host APIs.
- High-risk app-only identity and local-private features are excluded from web
  v1.
- The spec can be used to create a web implementation plan without changing the
  app-mediated relay/app security model.
