use yrs::{Doc, Transact, GetString, Text};
use yrs::ReadTxn;
use yrs::updates::decoder::Decode;

/// A Yrs document keyed by entity ID.
pub struct YrsDocument {
    doc: Doc,
}

impl YrsDocument {
    pub fn new() -> Self {
        YrsDocument { doc: Doc::new() }
    }

    /// Apply a binary delta (state vector update) to this document.
    pub fn apply_update(&self, update_bytes: &[u8]) -> Result<(), String> {
        let update = yrs::Update::decode_v1(update_bytes)
            .map_err(|e| format!("YrsDocument: decode update failed: {e:?}"))?;
        let mut txn = self.doc.transact_mut();
        txn.apply_update(update)
            .map_err(|e| format!("YrsDocument: apply update failed: {e:?}"))?;
        Ok(())
    }

    /// Encode the full document state as a binary delta (v1 format).
    pub fn encode_state(&self) -> Vec<u8> {
        let txn = self.doc.transact();
        txn.encode_state_as_update_v1(&Default::default())
    }

    /// Get the current text content of a named text type.
    pub fn get_text(&self, name: &str) -> String {
        let txn = self.doc.transact();
        self.doc.get_or_insert_text(name).get_string(&txn)
    }

    /// Insert text at a named text type (for post content).
    pub fn insert_text(&self, name: &str, content: &str) -> Vec<u8> {
        let text = self.doc.get_or_insert_text(name);
        {
            let mut txn = self.doc.transact_mut();
            text.insert(&mut txn, 0, content);
        }
        self.encode_state()
    }
}

impl Default for YrsDocument {
    fn default() -> Self {
        Self::new()
    }
}
