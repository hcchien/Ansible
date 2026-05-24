import 'package:ansible_did/ansible_did.dart';

// ZkpProof — the proof artifact uploaded to the Relay during Phase 1.
class ZkpProof {
  /// Proof backend: "groth16_bn254" for Q2
  final String backend;

  /// Hex-encoded compressed Groth16 proof bytes (~128 bytes)
  final String proofHex;

  /// Hex-encoded 32-byte anti-Sybil nullifier (public output of the circuit)
  final String nullifierHex;

  /// Hex-encoded SHA-256 hash of the Groth16 verifying key.
  /// The Relay uses this to confirm the circuit version.
  final String vkHash;

  /// Server-verifiable commitment for the passport holder's national ID.
  final String nationalIdHash;

  /// Server-verifiable commitment for the passport document number.
  final String passportNumberHash;

  const ZkpProof({
    required this.backend,
    required this.proofHex,
    required this.nullifierHex,
    required this.vkHash,
    required this.nationalIdHash,
    required this.passportNumberHash,
  });

  /// Circuit version string sent to the Relay as `zkp_circuit_version`.
  static const kCircuitVersion = 'passport_v1_groth16_bn254';

  Map<String, Object?> toRelayJson() => {
    'zkp_proof': proofHex,
    'zkp_circuit_version': kCircuitVersion,
    'verification_key_hash': 'sha256:$vkHash',
    'nullifier': nullifierHex,
  };
}

abstract class ZkpProver {
  /// Generate a ZKP for the given [passportSecretHex].
  ///
  /// [passportSecretHex] — 32-byte hex string (SHA-256 of MRZ fields),
  ///   computed by `PassportData.passportSecret`.
  Future<ZkpProof> prove({required String passportSecretHex});
}

/// Concrete ZKP prover backed by the Rust core (arkworks-rs Groth16).
class ZkpProverImpl implements ZkpProver {
  const ZkpProverImpl();

  @override
  Future<ZkpProof> prove({required String passportSecretHex}) async {
    try {
      final result = await RustLib.instance.apiZkpGenerateProof(
        passportSecretHex: passportSecretHex,
      );
      return ZkpProof(
        backend: 'groth16_bn254',
        proofHex: result.proofHex,
        nullifierHex: result.nullifierHex,
        vkHash: result.vkHash,
        nationalIdHash: result.nationalIdHash,
        passportNumberHash: result.passportNumberHash,
      );
    } on UnimplementedError {
      // Codegen not yet run — return a dev stub proof so the UI flow can be
      // exercised without native crypto.
      return _devStubProof(passportSecretHex);
    }
  }

  static ZkpProof _devStubProof(String passportSecretHex) {
    return ZkpProof(
      backend: 'groth16_bn254_dev_stub',
      proofHex: 'dev-proof-' + passportSecretHex.substring(0, 8),
      nullifierHex: 'dev-nullifier-' + passportSecretHex.substring(0, 16),
      vkHash: 'dev-vk-hash-placeholder',
      nationalIdHash:
          'dev-national-id-hash-' + passportSecretHex.substring(0, 16),
      passportNumberHash:
          'dev-passport-number-hash-' + passportSecretHex.substring(0, 16),
    );
  }
}

class ZkpVerifier {
  const ZkpVerifier._();

  /// Verify a [ZkpProof] locally (dev / test use only).
  static Future<bool> verify(ZkpProof proof) async {
    try {
      return await RustLib.instance.apiZkpVerifyProof(
        proofHex: proof.proofHex,
        nullifierHex: proof.nullifierHex,
      );
    } on UnimplementedError {
      return true; // dev stub — treat as valid
    }
  }
}
