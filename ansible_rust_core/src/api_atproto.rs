//! Flutter-exposed AT Protocol API functions.

use flutter_rust_bridge::frb;

pub use crate::atproto::lexicon::LexiconRecord;
pub use crate::atproto::did_plc::PlcGenesisOp;

/// Encode a Lexicon record to DAG-CBOR bytes.
/// Returns Err on serialization failure rather than panicking.
pub fn api_cbor_encode_record(record: LexiconRecord) -> Result<Vec<u8>, String> {
    crate::atproto::lexicon::cbor_encode_record(&record)
}

/// Compute CID v1 (DAG-CBOR, SHA2-256) from CBOR bytes.
#[frb(sync)]
pub fn api_compute_cid(cbor_bytes: Vec<u8>) -> String {
    crate::atproto::cid::compute_cid(&cbor_bytes)
}

/// Sign a Repo commit: Ed25519(cbor_bytes), return hex signature.
pub fn api_sign_commit(cbor_bytes: Vec<u8>, private_key_hex: String) -> Result<String, String> {
    crate::atproto::lexicon::sign_record_commit(&cbor_bytes, &private_key_hex)
}

/// Create a did:plc genesis op from an Ed25519 public key hex.
/// Returns Err on invalid key hex or serialization failure rather than panicking.
#[frb(sync)]
pub fn api_create_did_plc(signing_key_hex: String, handle: String, pds_endpoint: String) -> Result<PlcGenesisOp, String> {
    crate::atproto::did_plc::create_did_plc(signing_key_hex, handle, pds_endpoint)
}
