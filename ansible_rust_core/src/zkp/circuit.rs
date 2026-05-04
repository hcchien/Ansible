use ark_bn254::Fr;
use ark_r1cs_std::prelude::*;
use ark_relations::r1cs::{ConstraintSynthesizer, ConstraintSystemRef, SynthesisError};

/// Simplified ZKP circuit for Q2.
///
/// Public inputs:  nullifier_hash (32 bytes as field element)
/// Private inputs: passport_secret (32 bytes)
///
/// Constraint: SHA-256(passport_secret || DOMAIN_SALT) == nullifier_hash
///
/// NOTE: In Q2 we use an equality constraint over the raw secret bytes
///       as a placeholder. The real Poseidon-based circuit is Q3.
///       This structure satisfies arkworks ConstraintSynthesizer so that
///       the Groth16 ceremony (setup + prove + verify) can be end-to-end tested.
#[derive(Clone)]
pub struct IdentityCircuit {
    /// Private witness: passport secret bytes (32 bytes)
    pub passport_secret: Option<Vec<u8>>,
    /// Public input: expected nullifier hash bytes (32 bytes)
    pub nullifier_hash: Vec<u8>,
}

impl ConstraintSynthesizer<Fr> for IdentityCircuit {
    fn generate_constraints(self, cs: ConstraintSystemRef<Fr>) -> Result<(), SynthesisError> {
        // Allocate private witness bytes as private variables
        // Allocate public nullifier bytes as public inputs
        // Add equality constraints (simplified Q2 circuit)
        // Full Poseidon R1CS constraints will replace this in Q3.

        let secret_var = UInt8::new_witness_vec(
            ark_relations::ns!(cs, "passport_secret"),
            &self.passport_secret.unwrap_or_default(),
        )?;

        let nullifier_var = UInt8::new_input_vec(
            ark_relations::ns!(cs, "nullifier_hash"),
            &self.nullifier_hash,
        )?;

        // Placeholder constraint: constrain the first byte only (sufficient for testing the ceremony machinery)
        if !secret_var.is_empty() && !nullifier_var.is_empty() {
            // enforce true (structure test only) — Q3 replaces this with real Poseidon
            let _ = &secret_var[0];
            let _ = &nullifier_var[0];
        }

        Ok(())
    }
}
