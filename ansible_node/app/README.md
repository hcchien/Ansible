# ansible_node

Flutter desktop/mobile/web UI for running an Ansible node locally. This target shares domain + store packages from `ansible_core/` and is bootstrapped via the scripts in `ansible_cli/`.

## Getting Started

```bash
cd ansible_node/app
flutter pub get
flutter run -d macos   # or linux/windows/web
```

The app defaults to the local development environment. Override environment
settings with Flutter dart-defines:

```bash
flutter run -d macos \
  --dart-define=ANSIBLE_APP_ENV=dev \
  --dart-define=ANSIBLE_RELAY_BASE_URL=http://127.0.0.1:4001 \
  --dart-define=ANSIBLE_ISSUER_BASE_URL=http://localhost:4002 \
  --dart-define=ANSIBLE_ATPROTO_BASE_URL=http://127.0.0.1:4001
```

For staging or production builds, set the same keys to the deployed hosts. A
production build must use HTTPS, non-local endpoints, and disable insecure
fallbacks:

```bash
flutter build ios --release \
  --dart-define=ANSIBLE_APP_ENV=prod \
  --dart-define=ANSIBLE_RELAY_BASE_URL=https://relay.elix.cool \
  --dart-define=ANSIBLE_ISSUER_BASE_URL=https://issuer.elix.cool \
  --dart-define=ANSIBLE_ATPROTO_BASE_URL=https://relay.elix.cool \
  --dart-define=ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK=false \
  --dart-define=ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK=false
```

When `ANSIBLE_APP_ENV=prod`, the app fails fast on startup if relay, issuer, or
AT Protocol endpoints are local/insecure, or if either insecure fallback is
enabled.

## Standalone iOS Staging Install

Use the script below when installing a standalone release build onto a phone for
local staging testing:

```bash
cd ansible_node/app
scripts/install_ios_staging_release.sh --watchdog-clang-probe
```

By default it targets the current test iPhone
`00008101-00122CD93678001E`, uses the wireless device connection, detects the
Mac's `en0` IP, and builds with:

```text
ANSIBLE_APP_ENV=staging
ANSIBLE_USES_REAL_RUST_BRIDGE=true
ANSIBLE_ISSUER_BASE_URL=http://<local-ip>:4002
ANSIBLE_RELAY_BASE_URL=http://<local-ip>:4001
ANSIBLE_ATPROTO_BASE_URL=http://<local-ip>:4001
```

Override the defaults when needed:

```bash
IOS_DEVICE_ID=<device-udid> \
ANSIBLE_LOCAL_HOST_IP=10.0.0.58 \
scripts/install_ios_staging_release.sh --watchdog-clang-probe
```

Use `--dry-run` to confirm the resolved endpoints and Flutter command without
building or installing.

This flow intentionally uses `flutter run --release` instead of
`flutter install`: `flutter install` cannot accept dart-defines directly, and an
iOS release bundle built without the staging dart-defines starts with the default
`ANSIBLE_APP_ENV=dev`, which fails runtime readiness before `runApp()`.

### Xcode clang probe hang

With Xcode 26.5, release builds can stall after `Running Xcode build...` while a
SwiftBuildService child process runs a metadata probe like:

```text
clang -v -E -dM ... -c /dev/null
```

Sampling showed that probe blocked in `write()`. Killing only that stuck clang
probe let Xcode continue and complete the build. The script's
`--watchdog-clang-probe` option automates that workaround, scoped to descendant
processes of the current Flutter command and only for probes older than
`WATCHDOG_CLANG_PROBE_AFTER_SECONDS` seconds.
