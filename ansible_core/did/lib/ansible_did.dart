/// ansible_did — DID key management & Ed25519 signing
///
/// V1.1 Comp A: Identity & Security Core
///
/// This Dart library provides the interface layer; the heavy cryptography
/// (Ed25519 key generation, Secure Enclave / StrongBox storage) is
/// delegated to the Rust core via FFI (flutter_rust_bridge).
///
/// Phase 1 — Identity Anchoring:
///   1. [DidManager.generate]  → create Ed25519 keypair, store in Secure Enclave
///   2. [DidManager.toDid]     → encode public key as did:key (multibase)
///   3. ZKP generation lives in ansible_vc (arkworks-rs circuit via FFI)
///   4. Relay accepts [DID + ZKP + Nullifier] → marks DID as "Verified"
///
/// Phase 2 — Daily Operations (lightweight):
///   [DidSigner.sign] → Ed25519 sign over CRDT Op bytes using stored key

library ansible_did;

export 'src/did_manager.dart';
export 'src/did_signer.dart';
export 'src/did_document.dart';
export 'src/passkeys_manager.dart';
export 'src/did_plc_manager.dart';
// Generated flutter_rust_bridge API (RustLib + free functions + data types)
// plus the RustLibCompat extension that preserves the historical
// `RustLib.instance.apiX(...)` call style.
export 'src/rust_api.dart';
