/// Self-Issued Verifiable Credential derived from ePassport NFC data.
///
/// Conforms to W3C VC Data Model v2.0 (self-issued profile).
/// The issuer DID equals the subject DID — the passport holder issues
/// their own credential based on the chip's cryptographic proof.
///
/// This VC is the private input to the ZKP circuit; it is never
/// transmitted over the network in plaintext.
class SelfIssuedVc {
  /// Subject + Issuer DID (same for self-issued)
  final String did;

  /// Credential issuance timestamp
  final DateTime issuedAt;

  /// Credential expiry (should not exceed passport expiry)
  final DateTime expiresAt;

  /// Proof that the credential is bound to a valid ePassport chip.
  /// Contains the SOD signature verification result.
  final Map<String, dynamic> passportProof;

  const SelfIssuedVc({
    required this.did,
    required this.issuedAt,
    required this.expiresAt,
    required this.passportProof,
  });

  /// Build a Self-Issued VC from verified [PassportData].
  ///
  /// TODO(v1.1 Q2): validate SOD signature chain against CSCA root certs
  static SelfIssuedVc fromPassport({
    required String did,
    required dynamic passportData, // PassportData — avoid circular import
  }) {
    throw UnimplementedError(
      'SelfIssuedVc.fromPassport — pending NFC + Rust FFI in Q2',
    );
  }
}
