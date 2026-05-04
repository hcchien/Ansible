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
pub fn create_did_plc(signing_key_hex: String, handle: String, pds_endpoint: String) -> PlcGenesisOp {
    let did_key = encode_did_key(signing_key_hex);

    // Build services sub-object
    let mut pds_service: BTreeMap<String, serde_json::Value> = BTreeMap::new();
    pds_service.insert("type".to_string(), serde_json::Value::String("AtprotoPds".to_string()));
    pds_service.insert("endpoint".to_string(), serde_json::Value::String(pds_endpoint));

    let mut services: BTreeMap<String, serde_json::Value> = BTreeMap::new();
    services.insert(
        "atproto_pds".to_string(),
        serde_json::to_value(&pds_service).unwrap(),
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
        serde_json::to_value(&services).unwrap(),
    );
    op.insert(
        "signingKey".to_string(),
        serde_json::Value::String(did_key),
    );
    op.insert("type".to_string(), serde_json::Value::String("plc_genesis".to_string()));

    let genesis_json = serde_json::to_string(&op).expect("JSON serialization failed");

    // DEV ONLY (P1): DID suffix is computed from SHA-256 of JSON bytes.
    // The real plc.directory spec hashes a DAG-CBOR encoding of the genesis op,
    // so these DIDs are NOT compatible with the live PLC directory.
    // TODO(P2): replace JSON hashing with DAG-CBOR via ciborium.
    let hash = Sha256::digest(genesis_json.as_bytes());
    let did_suffix = base32_encode_nopad(&hash[..16]);
    let did = format!("did:plc:{}", did_suffix);

    PlcGenesisOp { did, genesis_json }
}
