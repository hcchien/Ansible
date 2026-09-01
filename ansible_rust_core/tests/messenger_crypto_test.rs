use ansible_rust_core::messenger::{
    create_messenger_device, decrypt_inbound_message, encrypt_initial_message,
    generate_one_time_pre_keys, MessengerEncryptInput,
};

#[test]
fn messenger_crypto_round_trip_encrypts_for_remote_device() {
    let alice = create_messenger_device("did:plc:alice".to_string()).unwrap();
    let mut bob = create_messenger_device("did:plc:bob".to_string()).unwrap();
    assert!(alice.signed_pre_key_id <= i32::MAX as u32);
    assert!(bob.signed_pre_key_id <= i32::MAX as u32);
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

#[test]
fn generated_pre_key_ids_do_not_repeat_across_replenishment_batches() {
    let mut device = create_messenger_device("did:plc:alice".to_string()).unwrap();
    let first = generate_one_time_pre_keys(&mut device, 20).unwrap();
    let second = generate_one_time_pre_keys(&mut device, 20).unwrap();

    let mut ids = first
        .iter()
        .chain(second.iter())
        .map(|key| key.pre_key_id)
        .collect::<Vec<_>>();
    ids.sort_unstable();
    ids.dedup();

    assert_eq!(ids.len(), 40);
    assert!(ids.iter().all(|id| *id <= i32::MAX as u32));
}

#[test]
fn one_time_pre_key_cannot_decrypt_a_replayed_initial_message() {
    let alice = create_messenger_device("did:plc:alice".to_string()).unwrap();
    let mut bob = create_messenger_device("did:plc:bob".to_string()).unwrap();
    let bob_pre_keys = generate_one_time_pre_keys(&mut bob, 1).unwrap();
    let ciphertext = encrypt_initial_message(MessengerEncryptInput {
        local_device: alice,
        remote_bundle: bob.public_bundle(bob_pre_keys[0].clone()),
        plaintext: b"single use".to_vec(),
    })
    .unwrap();

    decrypt_inbound_message(&mut bob, ciphertext.clone()).unwrap();
    assert_eq!(
        decrypt_inbound_message(&mut bob, ciphertext).unwrap_err(),
        "messenger_one_time_pre_key_missing"
    );
}
