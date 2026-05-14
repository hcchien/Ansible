use flutter_rust_bridge::frb;

pub use crate::messenger::{
    MessengerCiphertext, MessengerDevice, MessengerEncryptInput, MessengerPlaintext,
    MessengerPreKey, MessengerPreKeyBundle,
};

#[frb(sync)]
pub fn api_messenger_create_device(subject_did: String) -> Result<MessengerDevice, String> {
    crate::messenger::create_messenger_device(subject_did)
}

#[frb(sync)]
pub fn api_messenger_generate_pre_keys(
    mut device: MessengerDevice,
    count: u32,
) -> Result<Vec<MessengerPreKey>, String> {
    crate::messenger::generate_one_time_pre_keys(&mut device, count)
}

pub fn api_messenger_encrypt_initial_message(
    input: MessengerEncryptInput,
) -> Result<MessengerCiphertext, String> {
    crate::messenger::encrypt_initial_message(input)
}

pub fn api_messenger_decrypt_inbound_message(
    mut local_device: MessengerDevice,
    ciphertext: MessengerCiphertext,
) -> Result<MessengerPlaintext, String> {
    crate::messenger::decrypt_inbound_message(&mut local_device, ciphertext)
}
