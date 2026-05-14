use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    XChaCha20Poly1305, XNonce,
};
use hkdf::Hkdf;
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

const PROTOCOL_VERSION: &str = "signal-mvp-v1";
const CIPHERTEXT_TYPE: &str = "pre_key_signal_message";
const ROOT_KEY_INFO: &[u8] = b"ansible messenger signal-mvp-v1 root key";
const AEAD_KEY_INFO: &[u8] = b"ansible messenger signal-mvp-v1 aead key";
const SESSION_STATE_INFO: &[u8] = b"ansible messenger signal-mvp-v1 session state";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessengerDevice {
    pub subject_did: String,
    pub device_id: String,
    pub identity_key_public: String,
    pub identity_key_private: String,
    pub signed_pre_key_id: u32,
    pub signed_pre_key_public: String,
    pub signed_pre_key_private: String,
    pub signed_pre_key_signature: String,
    pub session_state: Option<String>,
    pub one_time_pre_keys: Vec<MessengerPreKey>,
    pub next_pre_key_id: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessengerPreKey {
    pub pre_key_id: u32,
    pub public_key: String,
    pub private_key: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessengerPreKeyBundle {
    pub subject_did: String,
    pub device_id: String,
    pub identity_key: String,
    pub signed_pre_key_id: u32,
    pub signed_pre_key: String,
    pub signed_pre_key_signature: String,
    pub one_time_pre_key_id: u32,
    pub one_time_pre_key: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessengerEncryptInput {
    pub local_device: MessengerDevice,
    pub remote_bundle: MessengerPreKeyBundle,
    pub plaintext: Vec<u8>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessengerCiphertext {
    pub protocol_version: String,
    pub ciphertext_type: String,
    pub ciphertext: Vec<u8>,
    pub updated_session_state: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MessengerPlaintext {
    pub body: Vec<u8>,
    pub updated_session_state: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct InitialMessageEnvelope {
    protocol_version: String,
    ciphertext_type: String,
    sender_did: String,
    sender_device_id: String,
    sender_identity_key: String,
    recipient_did: String,
    recipient_device_id: String,
    signed_pre_key_id: u32,
    one_time_pre_key_id: u32,
    ephemeral_key: String,
    nonce: String,
    body: String,
}

#[derive(Debug, Serialize)]
struct SessionState {
    protocol_version: String,
    role: String,
    local_did: String,
    local_device_id: String,
    remote_did: String,
    remote_device_id: String,
    root_key: String,
}

impl MessengerDevice {
    pub fn public_bundle(&self, one_time_pre_key: MessengerPreKey) -> MessengerPreKeyBundle {
        MessengerPreKeyBundle {
            subject_did: self.subject_did.clone(),
            device_id: self.device_id.clone(),
            identity_key: self.identity_key_public.clone(),
            signed_pre_key_id: self.signed_pre_key_id,
            signed_pre_key: self.signed_pre_key_public.clone(),
            signed_pre_key_signature: self.signed_pre_key_signature.clone(),
            one_time_pre_key_id: one_time_pre_key.pre_key_id,
            one_time_pre_key: one_time_pre_key.public_key,
        }
    }
}

pub fn create_messenger_device(subject_did: String) -> Result<MessengerDevice, String> {
    if subject_did.trim().is_empty() {
        return Err("messenger_subject_did_required".to_string());
    }

    let identity_secret = StaticSecret::random_from_rng(OsRng);
    let identity_public = PublicKey::from(&identity_secret);
    let signed_pre_key_secret = StaticSecret::random_from_rng(OsRng);
    let signed_pre_key_public = PublicKey::from(&signed_pre_key_secret);
    let signed_pre_key_id = random_u32_nonzero();

    Ok(MessengerDevice {
        subject_did,
        device_id: format!("msgdev_{}", random_b64(16)),
        identity_key_public: encode_bytes(identity_public.as_bytes()),
        identity_key_private: encode_bytes(identity_secret.to_bytes().as_slice()),
        signed_pre_key_id,
        signed_pre_key_public: encode_bytes(signed_pre_key_public.as_bytes()),
        signed_pre_key_private: encode_bytes(signed_pre_key_secret.to_bytes().as_slice()),
        signed_pre_key_signature: signed_pre_key_signature(
            identity_public.as_bytes(),
            signed_pre_key_public.as_bytes(),
            signed_pre_key_id,
        ),
        session_state: None,
        one_time_pre_keys: Vec::new(),
        next_pre_key_id: 1,
    })
}

pub fn generate_one_time_pre_keys(
    device: &mut MessengerDevice,
    count: u32,
) -> Result<Vec<MessengerPreKey>, String> {
    if count == 0 {
        return Ok(Vec::new());
    }

    let mut pre_keys = Vec::with_capacity(count as usize);
    for _ in 0..count {
        let secret = StaticSecret::random_from_rng(OsRng);
        let public = PublicKey::from(&secret);
        let pre_key = MessengerPreKey {
            pre_key_id: device.next_pre_key_id,
            public_key: encode_bytes(public.as_bytes()),
            private_key: encode_bytes(secret.to_bytes().as_slice()),
        };
        device.next_pre_key_id = device
            .next_pre_key_id
            .checked_add(1)
            .ok_or_else(|| "messenger_pre_key_id_exhausted".to_string())?;
        device.one_time_pre_keys.push(pre_key.clone());
        pre_keys.push(pre_key);
    }

    Ok(pre_keys)
}

pub fn encrypt_initial_message(
    input: MessengerEncryptInput,
) -> Result<MessengerCiphertext, String> {
    if input.plaintext.is_empty() {
        return Err("messenger_plaintext_required".to_string());
    }

    let local_identity_secret = decode_secret(&input.local_device.identity_key_private)?;
    let remote_identity_public = decode_public(&input.remote_bundle.identity_key)?;
    let remote_signed_pre_key = decode_public(&input.remote_bundle.signed_pre_key)?;
    let remote_one_time_pre_key = decode_public(&input.remote_bundle.one_time_pre_key)?;
    let ephemeral_secret = StaticSecret::random_from_rng(OsRng);
    let ephemeral_public = PublicKey::from(&ephemeral_secret);

    let root_key = derive_initial_root_key(&[
        local_identity_secret
            .diffie_hellman(&remote_signed_pre_key)
            .as_bytes(),
        ephemeral_secret
            .diffie_hellman(&remote_identity_public)
            .as_bytes(),
        ephemeral_secret
            .diffie_hellman(&remote_signed_pre_key)
            .as_bytes(),
        ephemeral_secret
            .diffie_hellman(&remote_one_time_pre_key)
            .as_bytes(),
    ])?;
    let aead_key = derive_key(&root_key, AEAD_KEY_INFO)?;
    let mut nonce = [0_u8; 24];
    OsRng.fill_bytes(&mut nonce);

    let aad = initial_aad(
        &input.local_device.subject_did,
        &input.local_device.device_id,
        &input.remote_bundle.subject_did,
        &input.remote_bundle.device_id,
        input.remote_bundle.signed_pre_key_id,
        input.remote_bundle.one_time_pre_key_id,
    );
    let encrypted_body = encrypt_body(&aead_key, &nonce, &aad, &input.plaintext)?;
    let envelope = InitialMessageEnvelope {
        protocol_version: PROTOCOL_VERSION.to_string(),
        ciphertext_type: CIPHERTEXT_TYPE.to_string(),
        sender_did: input.local_device.subject_did.clone(),
        sender_device_id: input.local_device.device_id.clone(),
        sender_identity_key: input.local_device.identity_key_public.clone(),
        recipient_did: input.remote_bundle.subject_did.clone(),
        recipient_device_id: input.remote_bundle.device_id.clone(),
        signed_pre_key_id: input.remote_bundle.signed_pre_key_id,
        one_time_pre_key_id: input.remote_bundle.one_time_pre_key_id,
        ephemeral_key: encode_bytes(ephemeral_public.as_bytes()),
        nonce: encode_bytes(&nonce),
        body: encode_bytes(&encrypted_body),
    };
    let session_state = serialize_session_state(SessionState {
        protocol_version: PROTOCOL_VERSION.to_string(),
        role: "sender".to_string(),
        local_did: input.local_device.subject_did,
        local_device_id: input.local_device.device_id,
        remote_did: input.remote_bundle.subject_did,
        remote_device_id: input.remote_bundle.device_id,
        root_key: encode_bytes(&derive_key(&root_key, SESSION_STATE_INFO)?),
    })?;

    Ok(MessengerCiphertext {
        protocol_version: PROTOCOL_VERSION.to_string(),
        ciphertext_type: CIPHERTEXT_TYPE.to_string(),
        ciphertext: serde_json::to_vec(&envelope)
            .map_err(|_| "messenger_ciphertext_encode_failed".to_string())?,
        updated_session_state: session_state,
    })
}

pub fn decrypt_inbound_message(
    device: &mut MessengerDevice,
    ciphertext: MessengerCiphertext,
) -> Result<MessengerPlaintext, String> {
    if ciphertext.protocol_version != PROTOCOL_VERSION {
        return Err("messenger_protocol_version_unsupported".to_string());
    }
    if ciphertext.ciphertext_type != CIPHERTEXT_TYPE {
        return Err("messenger_ciphertext_type_unsupported".to_string());
    }

    let envelope: InitialMessageEnvelope = serde_json::from_slice(&ciphertext.ciphertext)
        .map_err(|_| "messenger_ciphertext_decode_failed".to_string())?;
    if envelope.protocol_version != PROTOCOL_VERSION || envelope.ciphertext_type != CIPHERTEXT_TYPE
    {
        return Err("messenger_ciphertext_header_invalid".to_string());
    }
    if envelope.recipient_did != device.subject_did
        || envelope.recipient_device_id != device.device_id
        || envelope.signed_pre_key_id != device.signed_pre_key_id
    {
        return Err("messenger_ciphertext_recipient_mismatch".to_string());
    }

    let local_identity_secret = decode_secret(&device.identity_key_private)?;
    let local_signed_pre_key_secret = decode_secret(&device.signed_pre_key_private)?;
    let local_one_time_pre_key = device
        .one_time_pre_keys
        .iter()
        .find(|pre_key| pre_key.pre_key_id == envelope.one_time_pre_key_id)
        .cloned()
        .ok_or_else(|| "messenger_one_time_pre_key_missing".to_string())?;
    let local_one_time_pre_key_secret = decode_secret(&local_one_time_pre_key.private_key)?;
    let sender_identity_public = decode_public(&envelope.sender_identity_key)?;
    let ephemeral_public = decode_public(&envelope.ephemeral_key)?;

    let root_key = derive_initial_root_key(&[
        local_signed_pre_key_secret
            .diffie_hellman(&sender_identity_public)
            .as_bytes(),
        local_identity_secret
            .diffie_hellman(&ephemeral_public)
            .as_bytes(),
        local_signed_pre_key_secret
            .diffie_hellman(&ephemeral_public)
            .as_bytes(),
        local_one_time_pre_key_secret
            .diffie_hellman(&ephemeral_public)
            .as_bytes(),
    ])?;
    let aead_key = derive_key(&root_key, AEAD_KEY_INFO)?;
    let nonce = decode_fixed::<24>(&envelope.nonce)?;
    let body = decode_bytes(&envelope.body)?;
    let aad = initial_aad(
        &envelope.sender_did,
        &envelope.sender_device_id,
        &envelope.recipient_did,
        &envelope.recipient_device_id,
        envelope.signed_pre_key_id,
        envelope.one_time_pre_key_id,
    );
    let plaintext = decrypt_body(&aead_key, &nonce, &aad, &body)?;

    device
        .one_time_pre_keys
        .retain(|pre_key| pre_key.pre_key_id != envelope.one_time_pre_key_id);
    let session_state = serialize_session_state(SessionState {
        protocol_version: PROTOCOL_VERSION.to_string(),
        role: "recipient".to_string(),
        local_did: envelope.recipient_did,
        local_device_id: envelope.recipient_device_id,
        remote_did: envelope.sender_did,
        remote_device_id: envelope.sender_device_id,
        root_key: encode_bytes(&derive_key(&root_key, SESSION_STATE_INFO)?),
    })?;
    device.session_state = Some(session_state.clone());

    Ok(MessengerPlaintext {
        body: plaintext,
        updated_session_state: session_state,
    })
}

fn derive_initial_root_key(parts: &[&[u8]; 4]) -> Result<[u8; 32], String> {
    let mut material = Vec::with_capacity(32 * 4);
    for part in parts {
        material.extend_from_slice(part);
    }
    derive_key(&material, ROOT_KEY_INFO)
}

fn derive_key(material: &[u8], info: &[u8]) -> Result<[u8; 32], String> {
    let hk = Hkdf::<Sha256>::new(Some(PROTOCOL_VERSION.as_bytes()), material);
    let mut out = [0_u8; 32];
    hk.expand(info, &mut out)
        .map_err(|_| "messenger_key_derivation_failed".to_string())?;
    Ok(out)
}

fn encrypt_body(
    key: &[u8; 32],
    nonce: &[u8; 24],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, String> {
    let cipher = XChaCha20Poly1305::new(key.into());
    cipher
        .encrypt(
            XNonce::from_slice(nonce),
            chacha20poly1305::aead::Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| "messenger_encrypt_failed".to_string())
}

fn decrypt_body(
    key: &[u8; 32],
    nonce: &[u8; 24],
    aad: &[u8],
    ciphertext: &[u8],
) -> Result<Vec<u8>, String> {
    let cipher = XChaCha20Poly1305::new(key.into());
    cipher
        .decrypt(
            XNonce::from_slice(nonce),
            chacha20poly1305::aead::Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| "messenger_decrypt_failed".to_string())
}

fn initial_aad(
    sender_did: &str,
    sender_device_id: &str,
    recipient_did: &str,
    recipient_device_id: &str,
    signed_pre_key_id: u32,
    one_time_pre_key_id: u32,
) -> Vec<u8> {
    format!(
        "{PROTOCOL_VERSION}|{CIPHERTEXT_TYPE}|{sender_did}|{sender_device_id}|{recipient_did}|{recipient_device_id}|{signed_pre_key_id}|{one_time_pre_key_id}"
    )
    .into_bytes()
}

fn signed_pre_key_signature(
    identity_public: &[u8; 32],
    signed_pre_key_public: &[u8; 32],
    signed_pre_key_id: u32,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(PROTOCOL_VERSION.as_bytes());
    hasher.update(identity_public);
    hasher.update(signed_pre_key_public);
    hasher.update(signed_pre_key_id.to_be_bytes());
    encode_bytes(&hasher.finalize())
}

fn serialize_session_state(state: SessionState) -> Result<String, String> {
    serde_json::to_string(&state).map_err(|_| "messenger_session_state_encode_failed".to_string())
}

fn random_u32_nonzero() -> u32 {
    let value = OsRng.next_u32();
    if value == 0 {
        1
    } else {
        value
    }
}

fn random_b64(len: usize) -> String {
    let mut bytes = vec![0_u8; len];
    OsRng.fill_bytes(&mut bytes);
    encode_bytes(&bytes)
}

fn encode_bytes(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn decode_bytes(value: &str) -> Result<Vec<u8>, String> {
    URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| "messenger_base64_decode_failed".to_string())
}

fn decode_fixed<const N: usize>(value: &str) -> Result<[u8; N], String> {
    let bytes = decode_bytes(value)?;
    bytes
        .try_into()
        .map_err(|_| "messenger_key_length_invalid".to_string())
}

fn decode_secret(value: &str) -> Result<StaticSecret, String> {
    Ok(StaticSecret::from(decode_fixed::<32>(value)?))
}

fn decode_public(value: &str) -> Result<PublicKey, String> {
    Ok(PublicKey::from(decode_fixed::<32>(value)?))
}
