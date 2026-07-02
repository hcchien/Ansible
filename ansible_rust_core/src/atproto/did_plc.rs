use std::collections::BTreeMap;
use sha2::{Sha256, Digest};
use crate::did_key::encode_did_key;
use super::base32_encode_nopad;

/// The result of a did:plc genesis operation.
#[derive(Debug)]
pub struct PlcGenesisOp {
    pub did: String,
    pub genesis_json: String,
}

/// Create a did:plc genesis operation.
///
/// `signing_key_hex` — 32-byte Ed25519 public key, hex-encoded
/// Returns PlcGenesisOp with the did:plc identifier and canonical genesis JSON.
///
/// Returns `Err` (rather than panicking) on invalid key hex or serialization
/// failure; this is reachable from FFI and must never panic across the boundary.
pub fn create_did_plc(
    signing_key_hex: String,
    handle: String,
    pds_endpoint: String,
) -> Result<PlcGenesisOp, String> {
    let did_key = encode_did_key(signing_key_hex)?;

    // Build services sub-object
    let mut pds_service: BTreeMap<String, serde_json::Value> = BTreeMap::new();
    pds_service.insert("type".to_string(), serde_json::Value::String("AtprotoPds".to_string()));
    pds_service.insert("endpoint".to_string(), serde_json::Value::String(pds_endpoint));

    let mut services: BTreeMap<String, serde_json::Value> = BTreeMap::new();
    services.insert(
        "atproto_pds".to_string(),
        serde_json::to_value(&pds_service)
            .map_err(|e| format!("Failed to serialize PDS service: {}", e))?,
    );

    // Build top-level genesis op (BTreeMap for sorted keys)
    let mut op: BTreeMap<String, serde_json::Value> = BTreeMap::new();
    op.insert("handle".to_string(), serde_json::Value::String(handle));
    op.insert("prev".to_string(), serde_json::Value::Null);
    op.insert(
        "rotationKeys".to_string(),
        serde_json::Value::Array(vec![serde_json::Value::String(did_key.clone())]),
    );
    op.insert(
        "services".to_string(),
        serde_json::to_value(&services)
            .map_err(|e| format!("Failed to serialize services: {}", e))?,
    );
    op.insert(
        "signingKey".to_string(),
        serde_json::Value::String(did_key),
    );
    op.insert("type".to_string(), serde_json::Value::String("plc_genesis".to_string()));

    let genesis_json = serde_json::to_string(&op)
        .map_err(|e| format!("JSON serialization failed: {}", e))?;

    // DEV ONLY (P1): DID suffix is computed from SHA-256 of JSON bytes.
    // The real plc.directory spec hashes a DAG-CBOR encoding of the genesis op,
    // so these DIDs are NOT compatible with the live PLC directory.
    // TODO(P2): replace JSON hashing with DAG-CBOR via ciborium.
    let hash = Sha256::digest(genesis_json.as_bytes());
    let did_suffix = base32_encode_nopad(&hash[..16]);
    let did = format!("did:plc:{}", did_suffix);

    Ok(PlcGenesisOp { did, genesis_json })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_did_plc_valid_key_is_ok() {
        let pub_hex = "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29";
        let op = create_did_plc(
            pub_hex.to_string(),
            "alice.test".to_string(),
            "https://pds.example".to_string(),
        )
        .expect("valid inputs produce a genesis op");
        assert!(op.did.starts_with("did:plc:"));
        assert!(op.genesis_json.contains("plc_genesis"));
    }

    #[test]
    fn create_did_plc_bad_key_returns_err_not_panic() {
        let err = create_did_plc(
            "not-hex".to_string(),
            "alice.test".to_string(),
            "https://pds.example".to_string(),
        )
        .unwrap_err();
        assert!(err.contains("hex"), "unexpected error: {err}");
    }
}
