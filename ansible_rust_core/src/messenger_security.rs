//! Security metadata for Messenger crypto providers.
//!
//! This module is intentionally independent from the wire implementation. A
//! provider may only become production eligible after every property below is
//! backed by the implementation, interoperability tests, and an independent
//! review. Keeping that decision in code prevents the legacy compatibility
//! envelope from being mistaken for a complete Signal Protocol session.

pub const LEGACY_PROTOCOL_VERSION: &str = "signal-mvp-v1";
pub const LEGACY_PROVIDER_ID: &str = "ansible-legacy-initial-envelope";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MessengerSecurityProfile {
    pub provider_id: &'static str,
    pub protocol_version: &'static str,
    pub signed_pre_key_verification: bool,
    pub double_ratchet: bool,
    pub multi_device_session_management: bool,
    pub cross_client_vectors: bool,
    pub independent_review: bool,
}

impl MessengerSecurityProfile {
    pub const fn production_ready(self) -> bool {
        self.signed_pre_key_verification
            && self.double_ratchet
            && self.multi_device_session_management
            && self.cross_client_vectors
            && self.independent_review
    }
}

pub const LEGACY_SECURITY_PROFILE: MessengerSecurityProfile = MessengerSecurityProfile {
    provider_id: LEGACY_PROVIDER_ID,
    protocol_version: LEGACY_PROTOCOL_VERSION,
    signed_pre_key_verification: false,
    double_ratchet: false,
    multi_device_session_management: false,
    cross_client_vectors: false,
    independent_review: false,
};

pub fn security_profile_for(protocol_version: &str) -> Option<MessengerSecurityProfile> {
    match protocol_version {
        LEGACY_PROTOCOL_VERSION => Some(LEGACY_SECURITY_PROFILE),
        _ => None,
    }
}

pub fn require_production_ready(protocol_version: &str) -> Result<(), String> {
    match security_profile_for(protocol_version) {
        Some(profile) if profile.production_ready() => Ok(()),
        Some(_) => Err("messenger_crypto_provider_not_production_ready".to_string()),
        None => Err("messenger_protocol_version_unsupported".to_string()),
    }
}
