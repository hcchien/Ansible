use base64::{engine::general_purpose::STANDARD as B64, Engine};

/// Encode raw Yrs update bytes as base64 (transport format for OpsQueue payload).
pub fn encode_delta(bytes: &[u8]) -> String {
    B64.encode(bytes)
}

/// Decode a base64 OpsQueue payload back to raw Yrs update bytes.
pub fn decode_delta(b64: &str) -> Result<Vec<u8>, String> {
    B64.decode(b64).map_err(|e| format!("base64 decode failed: {e}"))
}
