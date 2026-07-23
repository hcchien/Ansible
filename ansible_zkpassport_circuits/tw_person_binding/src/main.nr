use commitment::nullify;
use data_check_expiry::check_expiry;
use utils::{
    get_mrz_from_dg1,
    types::{DG1Data, MRZExpiryDate, SaltedValue},
};

global TW_PERSON_NUMBER_START: u32 = 72;
global TW_PERSON_NUMBER_LENGTH: u32 = 10;
global TW_PERSON_BINDING_DOMAIN_LENGTH: u32 = 30;

fn ascii_digit(value: u8) -> u8 {
    assert(value >= 48);
    assert(value <= 57);
    value - 48
}

fn letter_value(value: u8) -> u8 {
    assert(value >= 65);
    assert(value <= 90);
    value - 55
}

fn validate_tw_national_id(id: [u8; TW_PERSON_NUMBER_LENGTH]) {
    let area = letter_value(id[0]);
    let area_tens = area / 10;
    let area_ones = area % 10;
    let weights = [8, 7, 6, 5, 4, 3, 2, 1];
    let mut sum = area_tens + area_ones * 9;
    for i in 0..8 {
        sum += ascii_digit(id[i + 1]) * weights[i];
    }
    sum += ascii_digit(id[9]);
    assert(sum % 10 == 0);
}

fn person_binding_input_from_id(id: [u8; TW_PERSON_NUMBER_LENGTH]) -> Field {
    validate_tw_national_id(id);
    let domain = "tris-aura:person-binding:tw:v1".as_bytes();
    let mut input = [0 as u8; TW_PERSON_BINDING_DOMAIN_LENGTH + TW_PERSON_NUMBER_LENGTH];
    for i in 0..TW_PERSON_BINDING_DOMAIN_LENGTH {
        input[i] = domain[i];
    }
    for i in 0..TW_PERSON_NUMBER_LENGTH {
        input[TW_PERSON_BINDING_DOMAIN_LENGTH + i] = id[i];
    }
    let digest = sha256::sha256_var(input, input.len());
    utils::pack_be_bytes_and_truncate_into_field::<32, 31>(digest)
}

fn person_binding_input(dg1: DG1Data) -> Field {
    let mrz = get_mrz_from_dg1(dg1);
    let mut id = [0 as u8; TW_PERSON_NUMBER_LENGTH];
    for i in 0..TW_PERSON_NUMBER_LENGTH {
        id[i] = mrz[TW_PERSON_NUMBER_START + i];
    }
    person_binding_input_from_id(id)
}

fn main(
    comm_in: pub Field,
    current_date: pub u64,
    salted_private_nullifier: SaltedValue<Field>,
    salted_expiry_date: SaltedValue<MRZExpiryDate>,
    salted_dg1: SaltedValue<DG1Data>,
    salted_dg2_hash: SaltedValue<Field>,
    salted_dg2_hash_type: SaltedValue<u32>,
    nullifier_secret: Field,
    oprf_proof: commitment::OPRFProof,
    service_scope: pub Field,
    service_subscope: pub Field,
) -> pub (Field, Field, Field, Field) {
    check_expiry(salted_dg1.value, current_date);
    let binding_input = person_binding_input(salted_dg1.value);
    let (scoped_nullifier, nullifier_type, oprf_pk_hash) = nullify(
        comm_in,
        salted_dg1,
        salted_expiry_date,
        salted_dg2_hash,
        salted_dg2_hash_type,
        salted_private_nullifier,
        service_scope,
        service_subscope,
        nullifier_secret,
        oprf_proof,
    );
    (binding_input, nullifier_type, scoped_nullifier, oprf_pk_hash)
}

#[test]
fn accepts_valid_tw_national_id_checksum() {
    let binding = person_binding_input_from_id("A123456789".as_bytes());
    assert(binding == 0x1037d8c7c8f25cdb65aa76b4b82da09b4ad4a12453cb0b39d553fc75d44fa7);
}

#[test(should_fail)]
fn rejects_invalid_tw_national_id_checksum() {
    validate_tw_national_id("A123456788".as_bytes());
}
