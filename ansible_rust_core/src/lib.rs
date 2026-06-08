//! ansible_rust_core — Tris-Aura V1.1 Comp A
//!
//! Ed25519 DID operations for the Tris-Aura identity layer.
//! Exposed to Dart via flutter_rust_bridge v2.

mod frb_generated; // flutter_rust_bridge generated glue (see setup_codegen.sh)

pub mod did_key;
pub mod signing;
pub mod api;
pub mod zkp;
pub mod crdt;
pub mod api_zkp;
pub mod api_crdt;
pub mod atproto;
pub mod api_atproto;
pub mod api_messenger;
pub mod messenger;
