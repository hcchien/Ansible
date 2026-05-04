//! flutter_rust_bridge CRDT API surface

use std::collections::HashMap;
use std::sync::Mutex;
use once_cell::sync::Lazy;
use flutter_rust_bridge::frb;
use crate::crdt::{doc::YrsDocument, delta};

static DOCS: Lazy<Mutex<HashMap<String, YrsDocument>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

/// Create or reset a Yrs document for [entityId].
#[frb(sync)]
pub fn api_crdt_init_doc(entity_id: String) {
    let mut docs = DOCS.lock().unwrap();
    docs.insert(entity_id, YrsDocument::new());
}

/// Insert text content into a named text field of a Yrs document.
///
/// Returns the base64-encoded binary delta to send as Op payload.
#[frb(sync)]
pub fn api_crdt_insert_text(entity_id: String, field_name: String, content: String) -> Result<String, String> {
    let docs = DOCS.lock().unwrap();
    let doc = docs.get(&entity_id)
        .ok_or_else(|| format!("No YrsDoc for entity_id: {entity_id}. Call api_crdt_init_doc first."))?;
    let state_bytes = doc.insert_text(&field_name, &content);
    Ok(delta::encode_delta(&state_bytes))
}

/// Apply a received delta (base64 payload from an Op) to a local Yrs document.
#[frb(sync)]
pub fn api_crdt_apply_delta(entity_id: String, payload_b64: String) -> Result<(), String> {
    let bytes = delta::decode_delta(&payload_b64)?;
    let docs = DOCS.lock().unwrap();
    let doc = docs.get(&entity_id)
        .ok_or_else(|| format!("No YrsDoc for entity_id: {entity_id}."))?;
    doc.apply_update(&bytes)
}

/// Get the current text content for a named field of a Yrs document.
#[frb(sync)]
pub fn api_crdt_get_text(entity_id: String, field_name: String) -> Result<String, String> {
    let docs = DOCS.lock().unwrap();
    let doc = docs.get(&entity_id)
        .ok_or_else(|| format!("No YrsDoc for entity_id: {entity_id}."))?;
    Ok(doc.get_text(&field_name))
}
