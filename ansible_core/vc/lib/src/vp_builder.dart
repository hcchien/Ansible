import 'tris_aura_credential.dart';

class VpBuilder {
  static Map<String, Object?> build({
    required TrisAuraCredential credential,
    required String holderDid,
    required String nonce,
    required String audience,
    required String proofValue,
    DateTime? createdAt,
  }) {
    if (credential.holderDid != holderDid) {
      throw TrisAuraCredentialException(
        'holder_mismatch',
        'Presentation holder must match credential subject.',
      );
    }

    final created = (createdAt ?? DateTime.now().toUtc()).toUtc();

    return {
      '@context': ['https://www.w3.org/ns/credentials/v2'],
      'type': ['VerifiablePresentation'],
      'holder': holderDid,
      'verifiableCredential': [credential.json],
      'proof': {
        'type': 'DataIntegrityProof',
        'cryptosuite': 'eddsa-jcs-2022',
        'verificationMethod': '$holderDid#key-1',
        'created': created.toIso8601String(),
        'proofPurpose': 'authentication',
        'challenge': nonce,
        'domain': audience,
        'proofValue': proofValue,
      },
    };
  }
}
