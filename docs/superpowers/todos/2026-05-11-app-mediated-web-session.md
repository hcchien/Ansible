# App-Mediated Web Session TODO

> Date: 2026-05-11  
> Source specs:
> - `docs/superpowers/specs/2026-05-11-app-mediated-web-session-design.md`
> - `docs/superpowers/specs/2026-05-09-federation-strategy-design.md`
> - `docs/superpowers/specs/2026-05-10-forum-host-board-design.md`
> Implementation plan:
> - `docs/superpowers/plans/2026-05-11-app-mediated-web-session.md`

## Phase 1: Relay Session Foundation

- [x] Add `WebSessionStore` for challenge, approval, session, expiry, and
  revocation state.
- [x] Add web-session challenge creation and polling endpoints.
- [x] Add approval/reject/revoke/me endpoints.
- [x] Verify app-signed grants against `IdentityCache` public keys.
- [x] Reject replayed, expired, malformed, or over-scoped grants.
- [x] Add `VerifyWebSession` plug for bearer token and scope checks.

## Phase 2: App Approval Foundation

- [x] Add canonical `WebSessionGrant` model.
- [x] Add grant signing service backed by `DidSigner`.
- [x] Add relay approval client.
- [x] Add deep-link parser for `trisaura://web-session/approve`.
- [x] Add QR scanner entry point for desktop-web login.
- [x] Add approval screen showing web origin, relay origin, scopes, expiry, and
  current DID.

## Phase 3: Web / Forum Host Integration

- [x] Add a scoped Forum Host smoke endpoint that requires `forum:post`.
- [x] Ensure web sessions expose `trust_tier: self_custody_did`.
- [x] Keep `basic_web` and `web_passkey` tiers distinct from app-approved DID
  sessions.
- [x] Define distribution frontend polling behavior for pending, approved,
  rejected, and expired challenges.
- [x] Store only relay-issued web session tokens in the browser.

## Phase 4: Security And Abuse Controls

- [x] Cap pending challenge lifetime.
- [x] Cap approved web session lifetime.
- [x] Bind grants to both relay origin and web origin.
- [x] Bind grants to the approving app device id.
- [x] Require explicit user approval before app signing.
- [x] Add user-visible session revocation.
- [x] Cap active app-approved web sessions per DID.
- [x] Rate-limit app device web-session approvals.
- [x] Apply DID-level rate limits to web Forum Host writes.
- [x] Rate-limit challenge creation attempts.
- [x] Keep raw DID and IP metadata separated in operational logs.

## Phase 5: Verification

- [x] Run relay web-session controller tests.
- [x] Run relay web-session auth plug tests.
- [x] Run Forum Host scoped endpoint tests.
- [x] Run app grant service tests.
- [x] Run app approval client tests.
- [x] Run app approval screen tests.
- [x] Run full `mix test` in `ansible_relay/phoenix`.
- [x] Run full `flutter test` in `ansible_node/app`.

## Decisions Captured

- [x] Self-custody web use is app-mediated in the first implementation.
- [x] The web frontend never receives the root DID private key.
- [x] Browser passkey login alone is not labeled as `self_custody_did`.
- [x] Delegated browser signing keys are excluded from the first implementation.
- [x] Web sessions are scoped and short-lived.
