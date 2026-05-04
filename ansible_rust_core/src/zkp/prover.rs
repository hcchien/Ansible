use std::sync::OnceLock;
use ark_bn254::{Bn254, Fr};
use ark_groth16::{Groth16, PreparedVerifyingKey, ProvingKey, Proof, r1cs_to_qap::LibsnarkReduction};
use ark_serialize::{CanonicalSerialize, CanonicalDeserialize};
use ark_snark::SNARK;
use rand::rngs::OsRng;

use super::circuit::IdentityCircuit;
use super::nullifier::compute_nullifier;

/// Lazy-initialised Groth16 proving key (circuit setup run once).
static PROVING_KEY: OnceLock<ProvingKey<Bn254>> = OnceLock::new();
static VERIFYING_KEY: OnceLock<PreparedVerifyingKey<Bn254>> = OnceLock::new();

/// Run the Groth16 trusted setup for IdentityCircuit.
/// This is called once on first use; subsequent calls are no-ops.
fn ensure_keys() {
    PROVING_KEY.get_or_init(|| {
        let placeholder_circuit = IdentityCircuit {
            passport_secret: Some(vec![0u8; 32]),
            nullifier_hash: vec![0u8; 32],
        };
        let (pk, vk) = Groth16::<Bn254, LibsnarkReduction>::circuit_specific_setup(
            placeholder_circuit,
            &mut OsRng,
        )
        .expect("Groth16 setup failed");
        let pvk = Groth16::<Bn254, LibsnarkReduction>::process_vk(&vk)
            .expect("process_vk failed");
        VERIFYING_KEY.get_or_init(|| pvk);
        pk
    });
}

/// Generate a Groth16 proof.
///
/// Returns (proof_bytes_hex, nullifier_hex, vk_hash_hex).
pub fn generate_proof(passport_secret_hex: &str) -> Result<(String, String, String), String> {
    ensure_keys();

    let nullifier_hex = compute_nullifier(passport_secret_hex)?;
    let nullifier_bytes = hex::decode(&nullifier_hex)
        .map_err(|e| format!("nullifier decode error: {e}"))?;

    let secret_bytes = hex::decode(passport_secret_hex)
        .map_err(|e| format!("secret decode error: {e}"))?;

    let circuit = IdentityCircuit {
        passport_secret: Some(secret_bytes),
        nullifier_hash: nullifier_bytes.clone(),
    };

    let pk = PROVING_KEY.get().unwrap();
    let _public_inputs = nullifier_bytes
        .iter()
        .map(|&b| Fr::from(b as u64))
        .collect::<Vec<_>>();

    let proof = Groth16::<Bn254, LibsnarkReduction>::prove(pk, circuit, &mut OsRng)
        .map_err(|e| format!("prove error: {e}"))?;

    let mut proof_bytes = Vec::new();
    proof
        .serialize_compressed(&mut proof_bytes)
        .map_err(|e| format!("serialize error: {e}"))?;

    // Compute a deterministic hash of the verifying key for circuit versioning
    let pvk = VERIFYING_KEY.get().unwrap();
    let vk_hash = {
        use sha2::{Sha256, Digest};
        // Use a string representation as stable hash input
        let vk_str = format!("{:?}", pvk.vk.alpha_g1);
        hex::encode(Sha256::digest(vk_str.as_bytes()))
    };

    Ok((hex::encode(proof_bytes), nullifier_hex, vk_hash))
}

/// Verify a Groth16 proof.
pub fn verify_proof(proof_hex: &str, nullifier_hex: &str) -> Result<bool, String> {
    ensure_keys();

    let proof_bytes = hex::decode(proof_hex)
        .map_err(|e| format!("proof_hex decode error: {e}"))?;
    let proof = Proof::<Bn254>::deserialize_compressed(proof_bytes.as_slice())
        .map_err(|e| format!("proof deserialize error: {e}"))?;

    let nullifier_bytes = hex::decode(nullifier_hex)
        .map_err(|e| format!("nullifier_hex decode error: {e}"))?;
    let public_inputs = nullifier_bytes
        .iter()
        .map(|&b| Fr::from(b as u64))
        .collect::<Vec<_>>();

    let pvk = VERIFYING_KEY.get().unwrap();
    let result = Groth16::<Bn254, LibsnarkReduction>::verify_with_processed_vk(
        pvk,
        &public_inputs,
        &proof,
    )
    .map_err(|e| format!("verify error: {e}"))?;

    Ok(result)
}
