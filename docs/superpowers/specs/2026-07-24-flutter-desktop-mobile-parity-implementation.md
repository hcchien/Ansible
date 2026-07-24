# Flutter Desktop / Mobile Capability Parity

> Status: Implemented
> Date: 2026-07-24

## Goal

Keep shared product behavior aligned across Flutter mobile and desktop while
representing native hardware differences honestly. “Parity” means the same
safe outcome and an understandable alternative, not displaying controls that
fail after the user starts them.

## Constitution Review

This implementation touches identity custody, credentials, sync, private-board
keys, notifications, and local AI access.

- Hardware custody is asserted only on iOS, Android, and macOS, where a native
  non-exportable P-256 implementation exists.
- Windows and Linux may create an explicitly consented reduced-trust identity
  stored in OS secure storage. They never receive hardware trust labels or
  sensitive issuer/private-board authority.
- Unsupported WebAuthn and credential hardware paths fail closed.
- Passport and Mobile MoICA data entry is not shown on platforms that cannot
  complete the native ceremony.
- Push and local AI controls are shown only where their declared platform
  boundary is available.
- No raw identity, credential, private key, or biometric data is added to logs,
  sync, or analytics.

This is consistent with Identity Autonomy, Data Autonomy, Minimal Disclosure,
and the constitution’s prohibition on silent custody downgrade.

## Capability Matrix

| Capability | iOS | Android | macOS | Windows | Linux |
| --- | --- | --- | --- | --- | --- |
| Hardware identity P-256 | Yes | Yes | Yes | No, explicit reduced trust | No, explicit reduced trust |
| WebAuthn sync | Yes | Yes | Yes | Yes | No, fail closed |
| Passport NFC | Yes | No | No | No | No |
| Mobile MoICA | Yes | Yes | No | No | No |
| Camera scanner | Yes | Yes | Yes | No | No |
| Wake push | APNS | Not yet | No | No | No |
| Local AI access | No | No | Bundled helper | PATH helper | PATH helper |
| App links | Yes | Yes | Yes | Yes | No |

## Implementation

- `PlatformCapabilities` is the only product-level source of native capability
  truth and is injectable in tests.
- Onboarding requires explicit reduced-trust consent where hardware identity is
  absent.
- macOS legacy identities can use the existing Secure Enclave rotation flow.
- Credential issuance and scanner controls are capability-gated before users
  enter data.
- Unsupported wake push is hidden while local notification preferences remain.
- Linux WebAuthn sync fails before network or mutation.
- Desktop adds compose/refresh shortcuts, focus capture, hover, tooltips, and a
  post context menu.
- Release CI continues compiling macOS, Windows, and Linux; widget tests verify
  the capability and interaction matrix.
