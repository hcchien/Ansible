# ansible_rust_core

**Tris-Aura V1.1 — Comp A: Identity & Security Core**

Ed25519 DID cryptography operations for the Ansible node, exposed to the Flutter/Dart layer via `flutter_rust_bridge` v2.

---

## Purpose

Implements the cryptographic foundation of Comp A:

- Ed25519 keypair generation
- `did:key` encoding/decoding (W3C spec)
- Message signing and signature verification
- All private key bytes are zeroized from Rust stack after use; callers must persist them in Secure Enclave (iOS) or StrongBox Keymaster (Android)

---

## Build

```bash
cargo build
```

For a release build:

```bash
cargo build --release
```

---

## Generate Dart bindings

One-time setup:

```bash
cargo install flutter_rust_bridge_codegen
```

From the repo root:

```bash
flutter_rust_bridge_codegen generate \
  --rust-input ansible_rust_core/src/api.rs \
  --dart-output ansible_core/did/lib/src/rust/frb_generated.dart \
  --rust-output ansible_rust_core/src/frb_generated.rs
```

After codegen, uncomment the `RustLib.instance.*` call sites in:
- `ansible_core/did/lib/src/did_manager.dart`
- `ansible_core/did/lib/src/did_signer.dart`

---

## Run tests

```bash
cargo test
```

---

## Key operations

| Function | Description | Notes |
|---|---|---|
| `api_generate_keypair()` | Generate new Ed25519 keypair | Returns `KeyPairBytes` with private hex, public hex, DID string |
| `api_encode_did_key(public_key_hex)` | Encode public key as `did:key` | Applies multicodec `0xed01` prefix + base58btc |
| `api_decode_did_key(did)` | Decode `did:key` to public key hex | Returns `Result<String, String>` |
| `api_sign_message(private_key_hex, message_hex)` | Sign message bytes | Async (no `#[frb(sync)]`); both args hex-encoded |
| `api_verify_signature(public_key_hex, message_hex, signature_hex)` | Verify Ed25519 signature | Returns `bool`; never panics |

---

## did:key encoding spec

Reference: https://w3c-ccg.github.io/did-method-key/

Encoding steps:
1. Take the raw 32-byte Ed25519 public key
2. Prepend multicodec varint prefix `0xed 0x01` (Ed25519 public key)
3. Encode the 34-byte result as base58btc
4. Prefix with `z` (multibase base58btc identifier)
5. Prepend `did:key:`

Example: `did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK`
