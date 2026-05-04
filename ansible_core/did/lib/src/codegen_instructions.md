# flutter_rust_bridge Codegen Instructions

After making changes to `ansible_rust_core/src/api.rs`, regenerate the Dart bindings:

## Setup (one-time)
```bash
cargo install flutter_rust_bridge_codegen
```

## Generate bindings
From the repo root:
```bash
flutter_rust_bridge_codegen generate \
  --rust-input ansible_rust_core/src/api.rs \
  --dart-output ansible_core/did/lib/src/rust/frb_generated.dart \
  --rust-output ansible_rust_core/src/frb_generated.rs
```

## After codegen
1. Import `frb_generated.dart` in `did_manager.dart` and `did_signer.dart`
2. Uncomment the `RustLib.instance.*` calls
3. Run `flutter pub get` in `ansible_core/did/`
