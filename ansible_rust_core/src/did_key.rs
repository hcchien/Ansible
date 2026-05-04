use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use zeroize::Zeroize;

/// Keypair bytes returned to Dart.
/// Private key is hex-encoded; caller must store it in Secure Enclave / StrongBox.
#[derive(Debug)]
pub struct KeyPairBytes {
    pub private_key_hex: String,
    pub public_key_hex: String,
    pub did: String,
}

/// Generate a new Ed25519 keypair and encode the public key as did:key.
pub fn generate_keypair() -> KeyPairBytes {
    let signing_key = SigningKey::generate(&mut OsRng);
    let verifying_key = signing_key.verifying_key();

    let mut private_bytes = signing_key.to_bytes();
    let private_key_hex = hex::encode(&private_bytes);
    private_bytes.zeroize(); // clear from stack

    let public_bytes = verifying_key.to_bytes();
    let public_key_hex = hex::encode(public_bytes);
    let did = encode_did_key(public_key_hex.clone());

    KeyPairBytes { private_key_hex, public_key_hex, did }
}

/// Encode a hex-encoded Ed25519 public key as a did:key string.
///
/// Spec: https://w3c-ccg.github.io/did-method-key/
/// Encoding: multibase base58btc of (0xed 0x01 || 32-byte pubkey), prefixed with 'z'
pub fn encode_did_key(public_key_hex: String) -> String {
    let bytes = hex::decode(&public_key_hex)
        .expect("public_key_hex must be valid hex");
    assert_eq!(bytes.len(), 32, "Ed25519 public key must be 32 bytes");

    // Multicodec prefix for Ed25519 public key: 0xed 0x01
    let mut prefixed = vec![0xed_u8, 0x01_u8];
    prefixed.extend_from_slice(&bytes);

    let encoded = bs58::encode(&prefixed).into_string();
    format!("did:key:z{}", encoded)
}

/// Extract the hex-encoded public key from a did:key string.
pub fn decode_did_key(did: String) -> Result<String, String> {
    let stripped = did
        .strip_prefix("did:key:z")
        .ok_or_else(|| format!("Invalid did:key format: {}", did))?;

    let decoded = bs58::decode(stripped)
        .into_vec()
        .map_err(|e| format!("Base58 decode failed: {}", e))?;

    if decoded.len() < 2 || decoded[0] != 0xed || decoded[1] != 0x01 {
        return Err("Not an Ed25519 did:key (expected 0xed01 multicodec prefix)".into());
    }

    Ok(hex::encode(&decoded[2..]))
}
