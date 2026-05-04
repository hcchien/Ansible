use sha2::{Sha256, Digest};

pub const DOMAIN_SALT: &[u8] = b"tris-aura.v1";

/// Compute the anti-Sybil nullifier.
///
/// nullifier = SHA-256(passport_secret_bytes || DOMAIN_SALT)
///
/// `passport_secret_hex` — 32-byte secret derived from ePassport MRZ,
///   computed on the app as SHA-256(documentNumber || dob || doe).
///
/// Returns 32 bytes as a hex string.
pub fn compute_nullifier(passport_secret_hex: &str) -> Result<String, String> {
    let secret_bytes = hex::decode(passport_secret_hex)
        .map_err(|e| format!("Invalid passport_secret_hex: {e}"))?;

    let mut hasher = Sha256::new();
    hasher.update(&secret_bytes);
    hasher.update(DOMAIN_SALT);
    let hash = hasher.finalize();
    Ok(hex::encode(hash))
}
