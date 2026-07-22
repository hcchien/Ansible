# Hardware Device Recovery Design

> Status: implementation contract
> Date: 2026-07-22
> Scope: mobile/desktop app, Relay identity anchors, private-board key envelopes,
> notifications, and recovery audit

## Goal

An Elix identity whose active signing key is non-exportable MUST remain usable
when a user adds, replaces, loses, or revokes a device. Recovery installs a new
hardware-held key and extends the self-certifying anchor chain; it never exports
or reconstructs the old hardware private key.

## Security Invariants

1. A device private key or identity private key never leaves platform secure
   hardware in hardware custody mode.
2. Relay is storage, delay enforcement, and notification infrastructure; it is
   not the sole recovery authority.
3. A new key is accepted only with one of:
   - approval by a currently enrolled device; or
   - a one-time, user-held recovery code configured while the identity key was
     available.
4. Recovery is pending for 72 hours by default. All enrolled devices are
   notified and any previously enrolled key can veto during the window.
5. Recovery codes are generated locally. Relay stores only SHA-256 hashes and a
   non-secret display hint; a successful code is consumed exactly once.
6. Device removal is a signed `device_change` anchor. The current device cannot
   accidentally revoke itself through the normal UI.
7. Private-board epoch keys are never uploaded in plaintext. A surviving member
   device re-wraps the active epoch key to a newly approved device. Revocation
   marks the board `rotation_required`, after which a new epoch excludes the
   revoked device.
8. Every configuration, approval, recovery, promotion, veto, device change, and
   private-board re-wrap/rotation is reason-coded in an append-only audit view.

## Lifecycle

### Add a device while an approved device survives

1. New device creates non-exportable identity and board-agreement keys.
2. New device displays an expiring QR request containing public material,
   current anchor CID, nonce, and fingerprint.
3. Existing device verifies the DID, current CID, expiry, and fingerprint, then
   signs the request.
4. Relay holds the recovery anchor during the grace period and sends a
   content-free identity alert to every enrolled device.
5. After promotion, a surviving member device registers the new board agreement
   key and re-wraps board epoch keys. No board plaintext or epoch key is handled
   by Relay.

### Recovery code

1. While signed in, the user generates ten high-entropy one-time codes locally.
2. The user must confirm one randomly selected code before hashes are registered.
3. On a replacement device, a code authorizes a new-key recovery anchor.
4. Relay atomically consumes the code only if the anchor is accepted as pending.
5. The normal grace, notification, veto, and promotion rules still apply.

### Lost device

The user uses another approved device or a recovery code. If neither exists,
the original identity cannot be recovered. Elix MUST explain this before
hardware upgrade and MUST NOT offer operator reset as a hidden fallback.

## API Surface

- `GET /api/v1/identity/anchor/:did/devices`
- `GET /api/v1/identity/anchor/:did/audit`
- `POST /api/v1/identity/recovery-codes`
- `GET /api/v1/identity/recovery-codes/:did/status`
- `POST /api/v1/identity/recovery-code/recover`
- Existing signed anchor submit, pending, promote, and veto endpoints remain the
  source of truth for key and device transitions.

Recovery-code configuration is signed by the current identity key over a
canonical JSON payload. Recovery submission contains a fully signed new-key
anchor plus the one-time code. Logs and responses never contain the code.

## Failure And UX Rules

- A pending recovery displays its deadline and an explicit “not active yet”
  state on the replacement device.
- Veto freezes the identity and requires a separate, audited resolution flow.
- Network errors never consume a recovery code.
- A failed or incomplete private-board re-wrap keeps that board locked on the
  new device; it never falls back to plaintext.
- Legacy encrypted private-key backup is labelled reduced trust and is not
  presented as the primary recovery mechanism for hardware custody.

## Constitution Review

1. **Identity involved:** user-controlled `did:elix`, non-exportable hardware
   identity keys, enrolled device keys, and board-scoped agreement keys.
2. **Data leaving the device:** public keys, signed anchor objects, one-time code
   hashes during setup, and a single code during explicit recovery. The user
   initiates every path.
3. **Minimum disclosure:** Relay learns only DID, public key material, device
   opaque IDs, hashes, reason codes, and timestamps.
4. **Excluded data:** no legal identity, biometric material, provider assertion,
   raw private key, board epoch key, or board plaintext is sent or logged.
5. **Trust/access effects:** recovery and revocation change signing authority;
   events are explicitly reason-coded and visible in audit.
6. **Personhood:** no personhood binding or duplicate-prevention identifier is
   created.
7. **Exit/revoke/rotate:** devices and codes can be revoked; identity keys and
   board epochs can be rotated; the chain is portable and independently
   verifiable.
8. **External hosts:** first-party Relay enforces this contract. External-host
   compliance remains discoverable and must not be silently assumed.

This design follows Constitution conflict priority by minimizing irreversible
identity harm, preserving explicit consent and self-custody, and retaining a
vetoable delay without granting the operator unilateral recovery authority.
