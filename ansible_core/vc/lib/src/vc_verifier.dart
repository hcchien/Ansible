import 'tris_aura_credential.dart';

enum CredentialStatus { active, revoked, suspended, expired, unknown }

abstract class ProofVerifier {
  bool verifyCredentialProof(TrisAuraCredential credential);
}

typedef CredentialStatusResolver =
    Future<CredentialStatus> Function(TrisAuraCredential credential);

class VcVerificationResult {
  final bool isValid;
  final String? error;

  const VcVerificationResult.valid() : isValid = true, error = null;

  const VcVerificationResult.invalid(this.error) : isValid = false;
}

class VcVerifier {
  final ProofVerifier proofVerifier;
  final Set<String> trustedIssuers;
  final CredentialStatusResolver statusResolver;

  VcVerifier({
    required this.proofVerifier,
    required this.trustedIssuers,
    required this.statusResolver,
  });

  VcVerificationResult verifyCredential(
    TrisAuraCredential credential, {
    required DateTime now,
  }) {
    if (!trustedIssuers.contains(credential.issuerDid)) {
      return const VcVerificationResult.invalid('untrusted_issuer');
    }
    if (!credential.hasType('VerifiableCredential')) {
      return const VcVerificationResult.invalid('missing_vc_type');
    }
    if (!credential.hasType('TrisAuraHumanityCredential')) {
      return const VcVerificationResult.invalid('unsupported_credential_type');
    }
    final utcNow = now.toUtc();
    if (utcNow.isBefore(credential.validFrom)) {
      return const VcVerificationResult.invalid('credential_not_active');
    }
    if (!utcNow.isBefore(credential.validUntil)) {
      return const VcVerificationResult.invalid('credential_expired');
    }
    if (!proofVerifier.verifyCredentialProof(credential)) {
      return const VcVerificationResult.invalid('invalid_proof');
    }
    return const VcVerificationResult.valid();
  }

  Future<VcVerificationResult> verifyCredentialStatus(
    TrisAuraCredential credential, {
    required DateTime now,
  }) async {
    final base = verifyCredential(credential, now: now);
    if (!base.isValid) return base;

    final status = await statusResolver(credential);
    switch (status) {
      case CredentialStatus.active:
        return const VcVerificationResult.valid();
      case CredentialStatus.revoked:
        return const VcVerificationResult.invalid('credential_revoked');
      case CredentialStatus.suspended:
        return const VcVerificationResult.invalid('credential_suspended');
      case CredentialStatus.expired:
        return const VcVerificationResult.invalid('credential_expired');
      case CredentialStatus.unknown:
        return const VcVerificationResult.invalid('credential_status_unknown');
    }
  }
}
