# ansible_node

Flutter desktop/mobile/web UI for running an Ansible node locally. This target shares domain + store packages from `ansible_core/` and is bootstrapped via the scripts in `ansible_cli/`.

## Getting Started

```bash
cd ansible_node/app
flutter pub get
flutter run -d macos   # or linux/windows/web
```

The Phase 1 identity anchoring flow talks to the local relay at
`http://127.0.0.1:4001` by default. Override it with:

```bash
flutter run -d macos --dart-define=ANSIBLE_RELAY_BASE_URL=http://127.0.0.1:4001
```
