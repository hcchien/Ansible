# Wallet Reputation Sync And User Presence

## Goal

Complete the existing Humanity VC path from the local Wallet to each active
Relay, and protect user-initiated outbound synchronization with device user
authentication.

## Behavior

- A manual sync asks iOS, Android, macOS, or the host OS to authenticate the
  current device user with biometrics or the device credential.
- Cancelling or failing authentication stops outbound synchronization without
  deleting or changing local data.
- After authentication, the app presents an active locally-held Humanity VC to
  every active Relay. The Relay verifies the holder and issuer proofs and
  remains authoritative for the resulting reputation tier.
- A user without a Humanity VC stays at the `basic` tier and may continue using
  all public, non-gated features.
- Automatic/background refresh is pull-only. It must not prompt for user
  presence, present credentials, or publish queued local changes.
- Content continues to be signed with the DID key. Device authentication is an
  authorization boundary for releasing signed outbound operations; it is not
  itself the content signature or proof of unique humanity.

## Constitution Review

This design follows the engineering constitution:

- Identity remains user-controlled and usable locally without a Relay.
- Humanity credentials are optional; no credential is required for public
  reading, local creation, or basic synchronization.
- Selective presentation happens only during an explicit user action, and the
  Relay receives the presentation rather than Wallet contents.
- Relay-derived reputation is cached locally as advisory state and is not
  treated as authority over local content or identity.
- Background work is pull-only, preserving offline/local-first behavior and
  avoiding surprise credential disclosure or signing prompts.

The current compliance review already identifies incomplete real WebAuthn and
VC-to-policy wiring. This change closes the Wallet-to-Relay presentation path
and adds a device-authentication boundary, but does not claim that platform
biometrics prove unique humanity or that the current passkeys-style storage is
full FIDO2/WebAuthn.

## Verification

- Unit-test that a Relay presentation updates the local cached tier.
- Widget-test that denied device authentication prevents manual sync.
- Test that pull-only synchronization does not enqueue or publish local data.
- Run Flutter analysis and the affected app test suite.
