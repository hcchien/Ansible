# Messenger Signal Provider Dependency Spike

**Date:** 2026-09-01
**Status:** Gate closed; migration foundation implemented; provider selection requires licensing clearance

## Goal

Replace the compatibility-only `signal-mvp-v1` initial pre-key envelope with a
maintained, reviewed Signal-compatible implementation that provides authentic
signed pre-keys, a Double Ratchet for ongoing messages, and asynchronous
multi-device session management. Existing local state and queued ciphertext
must remain distinguishable and readable during migration.

## Gate

A provider is production eligible only after all of the following are true:

1. signed pre-keys are digitally signed and verified before session creation;
2. each local/remote device pair has a persistent Double Ratchet session;
3. asynchronous multi-device session behavior is defined and tested;
4. cross-client vectors cover initial, ongoing, out-of-order, replay, key
   change, device add, and device revoke behavior;
5. the integrated provider, storage adapter, FFI boundary, and migration have
   passed independent cryptographic review; and
6. distribution licensing is compatible with the app's actual release
   channels.

The Rust `messenger_security` registry fails closed unless every property is
explicitly satisfied. The legacy provider is permanently registered as not
production ready.

## Candidate Assessment

### Signal `libsignal` v0.101.2 (`eb7864c`)

- **Technical fit:** strongest candidate. Signal documents that
  `libsignal-protocol` implements Signal Protocol including Double Ratchet, and
  the same repository is used by the official Android, iOS, and Desktop clients.
- **Maintenance:** active; v0.101.2 was released on 2026-08-28.
- **Integration:** the underlying implementation is Rust, so it can sit behind
  the existing Flutter Rust Bridge facade. The Rust API and dependency must be
  pinned because Signal says external use is unsupported and APIs may change
  without notice.
- **Blocking issue:** `AGPL-3.0-only`. This repository is currently MIT, and
  unresolved upstream questions specifically concern App Store distribution of
  the current Rust library without an additional permission. Do not link this
  dependency into release artifacts until legal/licensing clearance defines
  the repository license and Apple/Google distribution obligations.

Sources:

- <https://github.com/signalapp/libsignal/tree/v0.101.2>
- <https://github.com/signalapp/libsignal/blob/v0.101.2/README.md>
- <https://github.com/signalapp/libsignal/blob/v0.101.2/LICENSE>
- <https://github.com/signalapp/libsignal/issues/677>
- <https://github.com/signalapp/libsignal/issues/684>

### Permissive Rust alternatives

The alternatives found in this spike do not currently pass the gate. The
candidate implementations either explicitly state that they have not been
audited/security-reviewed or have small/incomplete maintenance histories and
open protocol hardening work. A permissive license is not a substitute for an
independent review.

No permissive implementation is selected.

## Migration Foundation

Schema v36 adds `protocol_version` to each local Messenger session and backfills
existing rows to `signal-mvp-v1`. New outgoing and incoming session writes copy
the actual envelope protocol version. This allows a future reviewed provider to:

1. dispatch state only to the provider that created it;
2. establish a new reviewed session for each device pair without parsing legacy
   state as ratchet state;
3. retain existing local message history;
4. reject unknown versions rather than guessing; and
5. remove legacy send support only after queued legacy ciphertext and device
   registrations have drained.

The Relay must continue to use an explicit protocol allow-list. A future wire
version is added only when its client implementation and vectors are ready; the
spike does not make an unimplemented protocol server-acceptable.

## Decision Required Before Provider Integration

Choose one of these routes:

1. obtain legal confirmation that linking and distributing the pinned official
   `libsignal` build is compatible with the intended open-source and app-store
   distribution model;
2. obtain a separate commercial/additional permission from Signal; or
3. fund/select a permissively licensed implementation and an independent audit,
   accepting that interoperability and ongoing maintenance become Tris-Aura's
   responsibility.

The technically preferred route is the pinned official library, conditional on
route 1 or 2. Until then, the cryptography gate remains closed and the product
must not describe `signal-mvp-v1` as Signal-grade encryption.

## Constitution Review

This spike follows the Tris-Aura Engineering Constitution:

- private identity, pre-key, and session state remains device-local and is
  stored through the secure-storage reference boundary;
- the Relay receives public pre-key material and opaque ciphertext only and has
  no decryption authority;
- unknown protocol/session versions fail closed;
- versioned state enables explicit migration, revocation, and removal instead
  of silent reinterpretation or server-forced reset; and
- current exportable secure-storage-backed Messenger secrets remain a documented
  reduced-trust path. This work does not claim to close the compliance review's
  broader hardware-backed key-custody gap.

The compliance claim is therefore limited: the migration design is
constitution-compatible, while production Signal-grade encryption and the
hardware-backed custody gap remain open.
