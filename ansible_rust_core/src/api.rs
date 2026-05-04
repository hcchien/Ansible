//! flutter_rust_bridge API surface — functions exposed to Dart
//!
//! After writing this file, run:
//!   flutter_rust_bridge_codegen generate
//! from the repo root to generate `ansible_core/did/lib/src/rust/` bindings.

use flutter_rust_bridge::frb;
use crate::did_key::{generate_keypair, encode_did_key, decode_did_key};
use crate::signing::{sign_message, verify_signature};

// Re-export the struct so flutter_rust_bridge can see it
pub use crate::did_key::KeyPairBytes;

/// Generate a new Ed25519 keypair. Returns private key hex + public key hex + DID string.
/// The caller MUST store private_key_hex in Secure Enclave / StrongBox immediately.
#[frb(sync)]
pub fn api_generate_keypair() -> KeyPairBytes {
    generate_keypair()
}

/// Encode a hex-encoded Ed25519 public key as a did:key string.
#[frb(sync)]
pub fn api_encode_did_key(public_key_hex: String) -> String {
    encode_did_key(public_key_hex)
}

/// Decode a did:key string back to a hex-encoded public key.
#[frb(sync)]
pub fn api_decode_did_key(did: String) -> Result<String, String> {
    decode_did_key(did)
}

/// Sign a message. Both inputs and output are hex-encoded.
/// Run on a background thread (not #[frb(sync)]) to avoid blocking Dart UI.
pub fn api_sign_message(private_key_hex: String, message_hex: String) -> Result<String, String> {
    sign_message(private_key_hex, message_hex)
}

/// Verify an Ed25519 signature. All inputs are hex-encoded.
#[frb(sync)]
pub fn api_verify_signature(
    public_key_hex: String,
    message_hex: String,
    signature_hex: String,
) -> bool {
    verify_signature(public_key_hex, message_hex, signature_hex)
}
