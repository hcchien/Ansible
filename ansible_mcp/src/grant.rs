//! Access-grant loading and validation (plan T-102).
//!
//! The grant file is written by the node app's "Local AI Access" settings
//! screen next to `ansible.db`. It is an intent record, not a secret: the OS
//! user boundary is the actual access control. This module fails closed —
//! missing, expired, or malformed grants deny every tool call (AC-1).
//!
//! The grant is re-read on every tool call so in-app revocation (deleting the
//! file) takes effect immediately.

use std::fmt;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde::de::{self, Deserializer, SeqAccess, Visitor};
use time::OffsetDateTime;

pub const GRANT_FILE: &str = "mcp_access_grant.json";

#[derive(Debug, Clone, Deserialize)]
pub struct Grant {
    pub grant_id: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
    /// DIDs the node app considers "the local user". Sourced from the grant so
    /// this binary never reads the hard-excluded `identities` table (D-5).
    #[serde(default)]
    pub local_author_dids: Vec<String>,
    pub scopes: Scopes,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Scopes {
    pub boards: BoardScope,
    #[serde(default)]
    pub include_murmurs: bool,
    #[serde(default)]
    pub include_follow_feed: bool,
}

/// `"all"` or an explicit list of board ids.
#[derive(Debug, Clone)]
pub enum BoardScope {
    All,
    Ids(Vec<String>),
}

impl BoardScope {
    pub fn allows(&self, board_id: &str) -> bool {
        match self {
            BoardScope::All => true,
            BoardScope::Ids(ids) => ids.iter().any(|id| id == board_id),
        }
    }
}

impl<'de> Deserialize<'de> for BoardScope {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct BoardScopeVisitor;

        impl<'de> Visitor<'de> for BoardScopeVisitor {
            type Value = BoardScope;

            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("the string \"all\" or a list of board ids")
            }

            fn visit_str<E: de::Error>(self, v: &str) -> Result<BoardScope, E> {
                if v == "all" {
                    Ok(BoardScope::All)
                } else {
                    Err(E::custom(format!(
                        "unknown board scope string {v:?}; expected \"all\" or a list"
                    )))
                }
            }

            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<BoardScope, A::Error> {
                let mut ids = Vec::new();
                while let Some(id) = seq.next_element::<String>()? {
                    ids.push(id);
                }
                Ok(BoardScope::Ids(ids))
            }
        }

        deserializer.deserialize_any(BoardScopeVisitor)
    }
}

#[derive(Debug)]
pub enum GrantError {
    Missing(PathBuf),
    Expired { expired_at: OffsetDateTime },
    Invalid(String),
}

impl GrantError {
    /// The structured denial shown to the AI client. It must be actionable for
    /// the human reading the model's relay of it, and must not leak content.
    pub fn denial_message(&self) -> String {
        match self {
            GrantError::Missing(path) => format!(
                "Access not granted. No local AI access grant was found at {}. \
                 Enable \"Local AI Access\" in the Ansible node app \
                 (Settings → Local AI Access) and retry.",
                path.display()
            ),
            GrantError::Expired { expired_at } => format!(
                "Access not granted. The local AI access grant expired at {expired_at}. \
                 Renew it in the Ansible node app (Settings → Local AI Access)."
            ),
            GrantError::Invalid(reason) => format!(
                "Access not granted. The local AI access grant could not be read ({reason}). \
                 Re-enable \"Local AI Access\" in the Ansible node app to rewrite it."
            ),
        }
    }
}

/// Load and validate the grant. Called on every tool call; the file is tiny
/// and re-reading keeps revocation immediate.
pub fn load(data_dir: &Path) -> Result<Grant, GrantError> {
    let path = data_dir.join(GRANT_FILE);
    let raw = match std::fs::read_to_string(&path) {
        Ok(raw) => raw,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            return Err(GrantError::Missing(path));
        }
        Err(err) => return Err(GrantError::Invalid(err.to_string())),
    };
    let grant: Grant =
        serde_json::from_str(&raw).map_err(|err| GrantError::Invalid(err.to_string()))?;
    if grant.expires_at <= OffsetDateTime::now_utc() {
        return Err(GrantError::Expired {
            expired_at: grant.expires_at,
        });
    }
    Ok(grant)
}
