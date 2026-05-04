use ed25519_dalek::{SigningKey, Signature, Signer, VerifyingKey, Verifier};

/// Sign a message with an Ed25519 private key.
///
/// `private_key_hex` — 32-byte signing key, hex-encoded
/// `message_hex`     — arbitrary message bytes, hex-encoded
///
/// Returns the 64-byte signature as hex.
pub fn sign_message(private_key_hex: String, message_hex: String) -> Result<String, String> {
    let key_bytes = hex::decode(&private_key_hex)
        .map_err(|e| format!("Invalid private key hex: {}", e))?;

    if key_bytes.len() != 32 {
        return Err(format!("Private key must be 32 bytes, got {}", key_bytes.len()));
    }

    let key_arr: [u8; 32] = key_bytes.try_into().unwrap();
    let signing_key = SigningKey::from_bytes(&key_arr);

    let message = hex::decode(&message_hex)
        .map_err(|e| format!("Invalid message hex: {}", e))?;

    let signature: Signature = signing_key.sign(&message);
    let sig_hex = hex::encode(signature.to_bytes());

    // zeroize key material
    drop(signing_key);

    Ok(sig_hex)
}

/// Verify an Ed25519 signature.
///
/// Returns true if valid, false if invalid (never panics).
pub fn verify_signature(
    public_key_hex: String,
    message_hex: String,
    signature_hex: String,
) -> bool {
    let verify = || -> Result<bool, anyhow::Error> {
        let pub_bytes = hex::decode(&public_key_hex)?;
        let pub_arr: [u8; 32] = pub_bytes.try_into()
            .map_err(|_| anyhow::anyhow!("Public key must be 32 bytes"))?;
        let verifying_key = VerifyingKey::from_bytes(&pub_arr)?;

        let message = hex::decode(&message_hex)?;

        let sig_bytes = hex::decode(&signature_hex)?;
        let sig_arr: [u8; 64] = sig_bytes.try_into()
            .map_err(|_| anyhow::anyhow!("Signature must be 64 bytes"))?;
        let signature = Signature::from_bytes(&sig_arr);

        Ok(verifying_key.verify(&message, &signature).is_ok())
    };

    verify().unwrap_or(false)
}
