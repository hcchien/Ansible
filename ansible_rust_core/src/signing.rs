use ed25519_dalek::{SigningKey, Signature, Signer, VerifyingKey, Verifier};
use zeroize::Zeroizing;

/// Sign a message with an Ed25519 private key.
///
/// `private_key_hex` — 32-byte signing key, hex-encoded
/// `message_hex`     — arbitrary message bytes, hex-encoded
///
/// Returns the 64-byte signature as hex.
///
/// Key material is held in `Zeroizing` wrappers so that both the decoded
/// `Vec<u8>` and the `[u8; 32]` stack copy are zeroed on drop.
/// `ed25519_dalek::SigningKey` also implements `ZeroizeOnDrop` (v2.x).
pub fn sign_message(private_key_hex: String, message_hex: String) -> Result<String, String> {
    // Zeroizing<Vec<u8>> zeroes the heap buffer when it goes out of scope.
    let key_bytes: Zeroizing<Vec<u8>> = Zeroizing::new(
        hex::decode(&private_key_hex)
            .map_err(|e| format!("Invalid private key hex: {}", e))?,
    );

    if key_bytes.len() != 32 {
        return Err(format!("Private key must be 32 bytes, got {}", key_bytes.len()));
    }

    // Zeroizing<[u8; 32]> zeroes the stack copy when it goes out of scope.
    let key_arr: Zeroizing<[u8; 32]> = Zeroizing::new(
        <[u8; 32]>::try_from(key_bytes.as_slice())
            .map_err(|_| "Private key must be 32 bytes".to_string())?,
    );
    // SigningKey (ed25519-dalek 2.x) implements ZeroizeOnDrop.
    let signing_key = SigningKey::from_bytes(&*key_arr);

    let message = hex::decode(&message_hex)
        .map_err(|e| format!("Invalid message hex: {}", e))?;

    let signature: Signature = signing_key.sign(&message);
    Ok(hex::encode(signature.to_bytes()))
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
