//! flutter_rust_bridge ZKP API surface
//! Exposed to Dart as RustLibZkp.* (merged into single RustLib by codegen).

use flutter_rust_bridge::frb;
use crate::zkp::prover;
use crate::zkp::nullifier;

/// Generate a Groth16 ZKP for a passport secret.
///
/// `passport_secret_hex` — 32-byte hex string (SHA-256 of MRZ fields).
///
/// Returns [ZkpResult] on success, or an error string.
pub fn api_zkp_generate_proof(passport_secret_hex: String) -> Result<ZkpResult, String> {
    let (proof_hex, nullifier_hex, vk_hash) =
        prover::generate_proof(&passport_secret_hex)?;
    Ok(ZkpResult { proof_hex, nullifier_hex, vk_hash })
}

/// Verify a Groth16 ZKP locally (for testing / dev mode).
pub fn api_zkp_verify_proof(proof_hex: String, nullifier_hex: String) -> Result<bool, String> {
    prover::verify_proof(&proof_hex, &nullifier_hex)
}

/// Compute the anti-Sybil nullifier without generating a full ZKP.
///
/// Use only for dev/testing; production code should use [api_zkp_generate_proof]
/// which returns the nullifier as part of the full proof.
#[frb(sync)]
pub fn api_zkp_compute_nullifier(passport_secret_hex: String) -> Result<String, String> {
    nullifier::compute_nullifier(&passport_secret_hex)
}

/// Returned by [api_zkp_generate_proof].
pub struct ZkpResult {
    /// Hex-encoded compressed Groth16 proof bytes.
    pub proof_hex: String,
    /// Hex-encoded 32-byte anti-Sybil nullifier.
    pub nullifier_hex: String,
    /// Hex-encoded SHA-256 hash of the Groth16 verifying key.
    /// The Relay validates this against its pinned ZKP key registry.
    pub vk_hash: String,
}
