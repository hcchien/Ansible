use sha2::{Sha256, Digest};
use super::base32_encode_nopad;

/// Write a unsigned varint to a vec.
fn write_varint(val: u64, out: &mut Vec<u8>) {
    let mut v = val;
    loop {
        let byte = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(byte);
            break;
        } else {
            out.push(byte | 0x80);
        }
    }
}

/// Compute CID v1 (DAG-CBOR, SHA2-256) from CBOR bytes.
/// Returns multibase base32lowercase string (prefix 'b'), no padding.
pub fn compute_cid(cbor_bytes: &[u8]) -> String {
    // SHA-256 hash of the CBOR bytes
    let hash = Sha256::digest(cbor_bytes);

    // Build multihash: varint(0x12) + varint(0x20) + 32-byte digest
    let mut multihash = Vec::with_capacity(34);
    write_varint(0x12, &mut multihash); // sha2-256 code
    write_varint(0x20, &mut multihash); // digest length = 32
    multihash.extend_from_slice(&hash);

    // Build CID bytes: varint(1) + varint(0x71) + multihash
    let mut cid_bytes = Vec::new();
    write_varint(1, &mut cid_bytes);    // CID version 1
    write_varint(0x71, &mut cid_bytes); // DAG-CBOR codec
    cid_bytes.extend_from_slice(&multihash);

    // Multibase base32 lowercase, prefix 'b'
    format!("b{}", base32_encode_nopad(&cid_bytes))
}
