pub mod cid;
pub mod lexicon;
pub mod did_plc;

/// Base32 lowercase alphabet (RFC 4648), no padding.
/// Shared by cid.rs and did_plc.rs.
pub(crate) fn base32_encode_nopad(data: &[u8]) -> String {
    const ALPHA: &[u8] = b"abcdefghijklmnopqrstuvwxyz234567";
    let mut out = Vec::new();
    let mut bits: u32 = 0;
    let mut bit_count: u32 = 0;

    for &byte in data {
        bits = (bits << 8) | (byte as u32);
        bit_count += 8;
        while bit_count >= 5 {
            bit_count -= 5;
            out.push(ALPHA[((bits >> bit_count) & 0x1f) as usize]);
        }
    }
    if bit_count > 0 {
        out.push(ALPHA[((bits << (5 - bit_count)) & 0x1f) as usize]);
    }
    // Every byte pushed comes from the ASCII-only `ALPHA` table, so the buffer is
    // always valid UTF-8. Use a lossy conversion instead of unwrap() so this
    // FFI-reachable helper can never panic even if the invariant is ever broken.
    String::from_utf8_lossy(&out).into_owned()
}
