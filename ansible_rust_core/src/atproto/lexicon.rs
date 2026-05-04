use std::collections::BTreeMap;
use ed25519_dalek::{SigningKey, Signer};

/// A minimal AT Protocol Lexicon record.
#[derive(Debug)]
pub struct LexiconRecord {
    pub type_: String,
    pub text: String,
    pub created_at: String,
    pub reply_to: Option<String>,
}

/// Encode a LexiconRecord as DAG-CBOR bytes (deterministic, sorted keys).
pub fn cbor_encode_record(rec: &LexiconRecord) -> Vec<u8> {
    let mut map: BTreeMap<&str, ciborium::Value> = BTreeMap::new();
    map.insert("$type", ciborium::Value::Text(rec.type_.clone()));
    map.insert("createdAt", ciborium::Value::Text(rec.created_at.clone()));
    map.insert("text", ciborium::Value::Text(rec.text.clone()));
    if let Some(reply) = &rec.reply_to {
        map.insert("replyTo", ciborium::Value::Text(reply.clone()));
    }

    let cbor_map: Vec<(ciborium::Value, ciborium::Value)> = map
        .into_iter()
        .map(|(k, v)| (ciborium::Value::Text(k.to_string()), v))
        .collect();

    let value = ciborium::Value::Map(cbor_map);
    let mut out = Vec::new();
    ciborium::ser::into_writer(&value, &mut out).expect("CBOR serialization failed");
    out
}

/// Sign CBOR bytes with an Ed25519 private key.
///
/// `private_key_hex` — 32-byte signing key hex-encoded
/// Returns hex-encoded 64-byte signature.
pub fn sign_record_commit(cbor_bytes: &[u8], private_key_hex: &str) -> Result<String, String> {
    let key_bytes = hex::decode(private_key_hex)
        .map_err(|e| format!("Invalid private key hex: {}", e))?;

    if key_bytes.len() != 32 {
        return Err(format!("Private key must be 32 bytes, got {}", key_bytes.len()));
    }

    let key_arr: [u8; 32] = key_bytes.try_into().unwrap();
    let signing_key = SigningKey::from_bytes(&key_arr);
    let signature = signing_key.sign(cbor_bytes);

    Ok(hex::encode(signature.to_bytes()))
}
