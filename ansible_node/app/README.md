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
  --dart-define=ANSIBLE_RELAY_BASE_URL=https://relay.trisaura.io \
  --dart-define=ANSIBLE_ISSUER_BASE_URL=https://issuer.trisaura.io \
  --dart-define=ANSIBLE_ATPROTO_BASE_URL=https://relay.trisaura.io \
  --dart-define=ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK=false \
  --dart-define=ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK=false
```

When `ANSIBLE_APP_ENV=prod`, the app fails fast on startup if relay, issuer, or
AT Protocol endpoints are local/insecure, or if either insecure fallback is
enabled.
