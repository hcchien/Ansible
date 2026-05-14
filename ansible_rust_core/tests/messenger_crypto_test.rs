use ansible_rust_core::messenger::{
    create_messenger_device, decrypt_inbound_message, encrypt_initial_message,
    generate_one_time_pre_keys, MessengerEncryptInput,
};

#[test]
fn messenger_crypto_round_trip_encrypts_for_remote_device() {
    let alice = create_messenger_device("did:plc:alice".to_string()).unwrap();
    let mut bob = create_messenger_device("did:plc:bob".to_string()).unwrap();
    let bob_pre_keys = generate_one_time_pre_keys(&mut bob, 1).unwrap();
    let bob_bundle = bob.public_bundle(bob_pre_keys[0].clone());

    let ciphertext = encrypt_initial_message(MessengerEncryptInput {
        local_device: alice.clone(),
        remote_bundle: bob_bundle,
        plaintext: b"hello bob".to_vec(),
    })
    .unwrap();

    assert_ne!(ciphertext.ciphertext, b"hello bob".to_vec());
    assert_eq!(ciphertext.protocol_version, "signal-mvp-v1");

    let plaintext = decrypt_inbound_message(&mut bob, ciphertext).unwrap();
    assert_eq!(plaintext.body, b"hello bob".to_vec());
}
