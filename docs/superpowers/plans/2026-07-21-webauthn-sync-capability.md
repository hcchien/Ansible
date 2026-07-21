# WebAuthn Assertion To Short-Lived Sync Capability

## Goal

Require an explicit standards-compliant WebAuthn user-verification ceremony
before an app releases locally signed writes to a Relay. A successful assertion
is exchanged for a short-lived capability limited to one DID, one Relay
audience, and the `sync:write` scope.

## Protocol

### Enrollment

1. The app requests registration options for its already anchored DID.
2. The Relay issues a single-use WebAuthn registration challenge.
3. The platform authenticator creates a discoverable passkey with user
   verification required.
4. The app signs the challenge ID and returned credential ID with its existing
   DID key. This prevents another party from enrolling a passkey against a
   public DID identifier.
5. The Relay verifies both the WebAuthn attestation ceremony and DID proof,
   then stores the credential ID, COSE public key, transports, and sign count.

### Manual sync authorization

1. The app requests authentication options for its DID and the `sync:write`
   scope.
2. The Relay returns a random, single-use challenge and only that DID's
   credential IDs.
3. The platform authenticator returns a WebAuthn assertion with user
   verification required.
4. The Relay verifies the challenge, RP ID, origin, user-presence and
   user-verification flags, signature, credential ownership, expiry, replay
   state, and monotonic sign count where supported.
5. The Relay returns an opaque capability valid for at most five minutes.
6. The app sends the capability as `Authorization: Bearer …` on outbound sync
   writes. The Relay binds it to the request's author DID and `sync:write`.

Background refresh stays pull-only and never requests or reuses a write
capability.

## Relying party configuration

- Production RP ID: `elix.cool`.
- Production origin: `https://elix.cool`.
- iOS/macOS applications require `webcredentials:elix.cool` in Associated
  Domains and an AASA response containing the app identifier.
- Android requires a valid Digital Asset Links association for
  `com.reviz.elix` and the release signing certificate.
- Development may override RP ID and permitted origin explicitly; insecure
  defaults are forbidden in release configuration.

## Capability format

The capability is an opaque, HMAC-authenticated token containing a random token
ID, subject DID, exact Relay audience, scopes, issued-at, and expiry. It is not
a content signature, identity credential, refresh token, or portable login
session. Rotation of the server secret invalidates outstanding capabilities.

## Constitution Review

- The passkey authorizes only outbound Relay writes; it never gates local
  create/list/read, identity access, export, or background pull.
- The DID signature remains the authorship proof for every operation. The
  capability is an additional release authorization and cannot replace it.
- A passkey is not a Humanity VC and must not raise reputation tier.
- Credentials are scoped to the RP and do not become a global identity or
  cross-Relay tracking identifier.
- Losing Relay state cannot erase the local identity or local content. A user
  may re-enroll through control of the DID key.
- No fallback silently bypasses WebAuthn in production. Development bypasses,
  if configured for tests, are explicit and fail closed by default.

This closes part of the compliance review's real-WebAuthn gap. It does not make
Relay availability a prerequisite for offline/local-first use.

## Rollout

During migration, challenge and enrollment endpoints are enabled first. Write
enforcement is controlled by a server configuration flag so existing released
clients are not instantly locked out. Production enables enforcement only
after a passkey-capable client has been distributed and users have an upgrade
path.
