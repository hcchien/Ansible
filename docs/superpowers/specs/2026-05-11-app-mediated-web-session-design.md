# App-Mediated Web Session Design Spec

> Status: Draft for implementation planning  
> Date: 2026-05-11  
> Scope: Distribution frontend, Ansible app, Forum Host / relay, DID signing,
> browser sessions, and trust-tier display

## Constitution Review

This spec touches identity, verification, Relay, Forum Host, AppView, and
authorization behavior, so the engineering constitution applies.

- The browser never receives the app user's root DID private key.
- App-mediated grants disclose only relay origin, web origin, target audience,
  scopes, subject DID, approving device id, and expiry.
- Browser sessions are short-lived, scoped, revocable, and audience-bound.
- Raw legal identity, provider assertions, biometrics, private keys, and
  personhood commitments must not appear in web-session payloads or logs.

## Goal

Let a user operate the distribution web UI with their app-held self-custody DID
without exporting the DID private key into the browser.

The distribution frontend must also support users who have not installed the app,
but those users should be represented as lower-trust web accounts until they
upgrade through app-mediated approval or another accepted verification path.

## Existing Context

The app already has the primitives needed to sign with a local DID:

- `PasskeysManager` creates and loads a device-held credential.
- `DidSigner.sign` signs arbitrary message bytes with the local DID private key.
- The relay already verifies Ed25519 signatures for identity anchoring and
  publication intents.

Current implementation status:

- Browser-to-app login challenge protocol exists as an MVP.
- QR/deep-link intake and app approval UI exist for web-session scopes.
- Relay challenge, approval, expiry, revocation, current-session, and
  session-list APIs exist.
- Forum Host web write APIs can require scoped web sessions with host audience.
- Hosted web/passkey account sessions and durable production session
  infrastructure remain future/partial.

## Design Decision

Use app-mediated web sessions as the first self-custody web path.

The web frontend never receives the user's root DID private key. Instead, the
relay issues a challenge and the app signs a short-lived grant after the user
confirms the origin, scopes, and expiry.

```text
Desktop web:
  web UI -> POST /api/v1/web-sessions/challenges
  web UI <- login_challenge + QR/deep-link payload

App approval:
  app scans QR or receives deep link
  app fetches challenge metadata from relay
  app shows origin, scopes, expiry, and DID
  app signs grant with DidSigner
  app -> POST /api/v1/web-sessions/approve

Browser session:
  web UI polls challenge status
  relay sets an httpOnly trisaura_session cookie after approval
  web UI calls scoped Forum Host APIs with same-origin credentials
```

## Trust Tiers

The relay must keep identity tier separate from login method:

| Tier | Meaning | Allowed MVP Behavior |
|---|---|---|
| `basic_web` | Hosted web account without app DID approval | Read, react, and limited posting after moderation/rate limits |
| `web_passkey` | Browser account authenticated by WebAuthn/passkey | Same as `basic_web`, with better account recovery and lower abuse score |
| `self_custody_did` | App-held DID approved the current web session | Post/reply as that DID within granted scope |
| `verified_human` | DID/account has accepted VC or reputation upgrade | Higher limits and provenance label |

The UI should display the tier where provenance matters. A web passkey account is
not automatically equivalent to an app-held self-custody DID.

## Session Grant

The app signs a canonical JSON grant:

```json
{
  "type": "io.trisaura.webSessionGrant",
  "version": 1,
  "challenge_id": "wsc_01J...",
  "relay_origin": "https://relay.elix.cool",
  "web_origin": "https://elix.cool",
  "audience": "https://forum.elix.cool",
  "subject_did": "did:plc:...",
  "approving_device_id": "app_device_...",
  "scopes": ["forum:read", "forum:post", "forum:reply"],
  "expires_at": "2026-05-11T13:00:00Z",
  "created_at": "2026-05-11T12:45:00Z"
}
```

Signing rules:

- Canonicalize the grant before signing.
- Bind the grant to both relay origin and web origin.
- Bind the grant to the intended Forum Host audience when present.
- Bind the grant to one relay-issued challenge id.
- Bind the grant to the app device that approved the browser session.
- Require expiry.
- Reject grants whose scopes exceed the original challenge request.
- Reject replay after the challenge is consumed.

## Web Session Abuse Policy

App device limits protect DID custody, but relay-side web session limits still
control browser abuse after approval.

Policy:

- Challenge lifetime defaults to 5 minutes and is capped at 15 minutes.
- App-approved web sessions default to 12 hours in the app approval flow.
- Relay rejects any web session grant longer than 24 hours.
- A DID may have at most 5 active app-approved web sessions at the same time.
- A single approving app device may approve at most 3 new web sessions per DID
  per rolling hour.
- Challenge creation attempts consume peer-level abuse tokens keyed by redacted
  network metadata, so a browser cannot create unlimited pending approvals.
- Forum Host write APIs consume DID-level abuse tokens, so all browser sessions
  for the same DID share posting/reply quota.
- A single browser session can still be revoked independently.
- Web session list APIs must expose active sessions for user-visible review and
  revocation.
- Session revocation uses the current httpOnly cookie in the browser path and
  may revoke either the current session or another active session for the same
  DID. Bearer tokens may be accepted for server/API compatibility, but the web
  frontend must not store bearer tokens.
- Operational logs must record rate-limit decisions with `subject_type` and a
  one-way `subject_hash`; they must not join raw DID strings and raw IP
  addresses in the same log event.

This means opening more browsers does not multiply the user's write quota. The
relay treats app approval as identity authorization, then applies quota at the
subject DID/account level.

## Scope Model

MVP scopes:

- `forum:read`: read session-owned private web state and subscribed boards.
- `forum:post`: create top-level hosted board threads through Forum Host APIs.
- `forum:reply`: create replies through Forum Host APIs.
- `identity:display`: let web display DID, handle, trust tier, and public
  provenance.

MVP deliberately excludes:

- Delegated long-lived browser signing keys.
- Root DID key export/import through the web UI.
- ActivityPub inbox/outbox implementation in the app.
- Unlimited session lifetime.
- Admin/moderator scopes.

## Relay Responsibilities

The relay owns:

- Challenge creation and expiry.
- Session grant verification.
- Session issuance, cookie installation, and revocation.
- Scope enforcement on web-facing write APIs.
- Trust tier labels and rate limits.
- Audit records that do not join raw IP metadata with raw DID values in logs.

The browser path should use a short-lived httpOnly `trisaura_session` cookie.
Challenge creation stays unauthenticated; challenge polling must use
same-origin credentials so the approved `Set-Cookie` response is accepted by
the browser. Bearer tokens remain a compatibility path for non-browser callers.
The first implementation may use an in-memory session store for dev, but the API
contract must allow durable storage before production.

## App Responsibilities

The app owns:

- Receiving a QR/deep-link payload.
- Fetching challenge metadata from the relay.
- Showing a clear approval screen with origin, scopes, expiry, and DID.
- Signing only after explicit user confirmation.
- Letting the user revoke active web sessions.

The app must reject unknown relay origins, expired challenges, malformed scope
requests, and grants that ask for scopes the app does not understand.

## Web Responsibilities

The distribution frontend owns:

- Starting the login challenge.
- Rendering QR/deep-link login.
- Polling challenge status: keep polling while `pending`, accept the relay-set
  httpOnly cookie and stop when `approved`, clear challenge state and offer
  retry when `rejected` or `expired`.
- Storing no bearer session token in browser storage. Legacy token helpers are
  no-ops kept only for compatibility.
- Calling Forum Host APIs with same-origin credentials so the browser sends the
  httpOnly cookie.
- Showing identity tier and provenance.

## Failure Behavior

- Expired challenge: web must restart login.
- User rejects approval: relay marks challenge rejected and web shows a retryable
  sign-in state.
- App offline: web polling remains pending until challenge expiry.
- Scope mismatch: relay rejects approval.
- Session expired: web must request a new app approval.
- DID no longer active: relay rejects approval and any session refresh.

## Acceptance Criteria

- Spec and plan state that app-mediated web sessions do not export DID keys to
  the browser.
- Relay has challenge, approval, polling, session, expiry, and revocation APIs.
- App can open a deep-link or QR payload, show approval, and sign a canonical
  session grant.
- Relay verifies app signatures against active DID cache before issuing a web
  session.
- Forum Host web write APIs can require `forum:post` or `forum:reply` scope.
- Web sessions have explicit trust tier and expiry.
- Basic/passkey web accounts remain allowed but are not labeled as
  `self_custody_did`.
