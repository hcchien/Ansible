use ed25519_dalek::{Signature, VerifyingKey, Verifier};
use rustler::{Binary, Error as RustlerError, NifResult};

rustler::atoms! {
    ok,
    error,
    invalid_public_key,
    invalid_signature,
    invalid_input,
}

/// Verify an Ed25519 signature.
///
/// Arguments:
///   - `public_key_hex` — hex-encoded 32-byte Ed25519 public key
///   - `message`        — raw message bytes (Erlang binary)
///   - `signature_hex`  — hex-encoded 64-byte Ed25519 signature
///
/// Returns `true` if valid, `false` if invalid.
#[rustler::nif]
fn verify_ed25519(
    public_key_hex: &str,
    message: Binary,
    signature_hex: &str,
) -> NifResult<bool> {
    let pub_bytes = hex::decode(public_key_hex)
        .map_err(|_| RustlerError::Atom("invalid_public_key"))?;
    let pub_arr: [u8; 32] = pub_bytes
        .try_into()
        .map_err(|_| RustlerError::Atom("invalid_public_key"))?;
    let verifying_key = VerifyingKey::from_bytes(&pub_arr)
        .map_err(|_| RustlerError::Atom("invalid_public_key"))?;

    let sig_bytes = hex::decode(signature_hex)
        .map_err(|_| RustlerError::Atom("invalid_signature"))?;
    let sig_arr: [u8; 64] = sig_bytes
        .try_into()
        .map_err(|_| RustlerError::Atom("invalid_signature"))?;
    let signature = Signature::from_bytes(&sig_arr);

    Ok(verifying_key.verify(message.as_slice(), &signature).is_ok())
}

rustler::init!("Elixir.AnsibleRelay.SigVerifierNIF", [verify_ed25519]);
