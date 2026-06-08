import 'package:ansible_did/ansible_did.dart';

/// The Tris-Aura V1.1 domain salt for nullifier computation.
const kDomainSalt = 'tris-aura.v1';

/// A computed Nullifier value (public output of the ZKP circuit).
class Nullifier {
  /// Hex-encoded 32-byte hash
  final String hex;
  const Nullifier(this.hex);

  @override
  String toString() => hex;

  @override
  bool operator ==(Object other) => other is Nullifier && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;
}

/// Seed inputs for nullifier derivation.
class NullifierSeed {
  /// Hex-encoded passport secret (SHA-256 of MRZ fields)
  final String passportSecretHex;
  const NullifierSeed({required this.passportSecretHex});
}

abstract class NullifierComputer {
  Future<Nullifier> compute(NullifierSeed seed);
}

/// Concrete nullifier computer backed by the Rust core.
///
/// Computes: SHA-256(passport_secret_bytes || domain_salt_bytes)
/// (Poseidon in Q3)
class NullifierComputerImpl implements NullifierComputer {
  const NullifierComputerImpl();

  @override
  Future<Nullifier> compute(NullifierSeed seed) async {
    try {
      final hex = apiZkpComputeNullifier(
        passportSecretHex: seed.passportSecretHex,
      );
      return Nullifier(hex);
    } on UnimplementedError {
      // Dev stub
      return Nullifier('dev-nullifier-${seed.passportSecretHex.substring(0, 16)}');
    }
  }
}
