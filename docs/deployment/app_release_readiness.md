# Elix App Release Readiness

## Scope

This runbook covers release candidates for Android, iOS, macOS, Windows, and
Linux. The registered Google Play application ID is `com.reviz.elix`. Apple
targets use the same bundle identifier unless App Store Connect has already
reserved another identifier.

Production builds consume
`ansible_node/app/config/production.json` through Flutter's
`--dart-define-from-file` option. The file contains public service locations and
security switches only; signing credentials never belong in the repository.

## Constitution Review

- Identity remains user-controlled and independent of any one Relay or store
  account. A store signature identifies the distributed binary, not a user.
- Production config disables insecure signing and identity fallbacks and
  requires the real Rust bridge.
- Relay, Issuer, AT Protocol, and Forum URLs are explicit HTTPS distribution
  paths. Private/local-only content semantics are unchanged and remain
  fail-closed.
- No private key, credential, legal identity field, provider assertion, or
  biometric material is added to build config, CI logs, or release artifacts.
- The current compliance review and roadmap must be reconciled before a public
  launch claim: custody-class/reduced-trust labeling must be verified in the
  shipped UI and documentation.

## Local verification

From `ansible_node/app`:

```bash
flutter analyze
flutter test
flutter test test/release_readiness_test.dart test/android_release_readiness_test.dart
```

Unsigned platform compilation checks may use:

```bash
flutter build ios --release --no-codesign --dart-define-from-file=config/production.json
flutter build macos --release --dart-define-from-file=config/production.json
flutter build windows --release --dart-define-from-file=config/production.json
flutter build linux --release --dart-define-from-file=config/production.json
```

## Android signing secrets

The release workflow requires these GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

The keystore is decoded only into the ephemeral runner workspace. Gradle reads
an ephemeral `android/key.properties`; both it and all keystore formats remain
gitignored. Google Play App Signing should hold the app-signing key; CI should
use the upload key.

## Apple distribution inputs

An App Store/TestFlight release additionally requires an Apple Distribution
certificate, matching provisioning profile, App Store Connect API key, and an
export options plist. macOS distribution additionally requires Developer ID
Application signing and notarization credentials. These values must be GitHub
environment secrets or supplied by a trusted release workstation.

## Release gate

A public release requires all of the following:

1. Flutter analyze and tests pass.
2. Production runtime-readiness tests pass.
3. Platform release binary compiles with the real Rust bridge.
4. Store/distribution signature is verified on the final artifact.
5. A clean-device smoke test covers create, list, read, local search, sync,
   backup/recovery, share links, and offline restart.
6. Privacy, terms, account-deletion, and store data-safety declarations match
   observed behavior.
7. The constitution launch blockers are either closed or explicitly resolved
   by an updated compliance review.
