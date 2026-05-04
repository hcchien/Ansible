import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';

class VcPresentationEnvelope {
  final String credentialId;
  final Map<String, Object?> verifiablePresentation;

  VcPresentationEnvelope({
    required this.credentialId,
    required this.verifiablePresentation,
  });
}

abstract class VpProofSigner {
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  });
}

class UnsupportedVpProofSigner implements VpProofSigner {
  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) {
    throw UnsupportedError('VP proof signing is not connected yet.');
  }
}

class JsonCredentialPayloadDecoder {
  Map<String, Object?> decode(String encryptedPayload) {
    final decoded = jsonDecode(encryptedPayload);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw const FormatException(
      'Credential payload must decode to a JSON object.',
    );
  }
}

typedef PresentationIdFactory = String Function();

class VcPresentationService {
  final WalletRepository walletRepository;
  final Set<String> trustedIssuers;
  final ProofVerifier proofVerifier;
  final CredentialStatusResolver statusResolver;
  final VpProofSigner proofSigner;
  final JsonCredentialPayloadDecoder payloadDecoder;
  final PresentationIdFactory presentationIdFactory;

  VcPresentationService({
    required this.walletRepository,
    required this.trustedIssuers,
    required this.proofVerifier,
    required this.statusResolver,
    required this.proofSigner,
    JsonCredentialPayloadDecoder? payloadDecoder,
    PresentationIdFactory? presentationIdFactory,
  }) : payloadDecoder = payloadDecoder ?? JsonCredentialPayloadDecoder(),
       presentationIdFactory =
           presentationIdFactory ??
           (() => 'vp-${DateTime.now().microsecondsSinceEpoch}');

  Future<VcPresentationEnvelope?> createForPost({
    required String holderDid,
    required String audience,
    required String nonce,
    required DateTime now,
  }) async {
    final credentials = await walletRepository.listCredentials();

    for (final metadata in credentials) {
      if (!_isCandidate(metadata, holderDid)) {
        continue;
      }

      final encryptedPayload = await walletRepository.getEncryptedPayload(
        metadata.credentialId,
      );
      if (encryptedPayload == null) {
        continue;
      }

      final TrisAuraCredential credential;
      try {
        credential = TrisAuraCredential.fromJson(
          payloadDecoder.decode(encryptedPayload),
        );
      } on Object {
        continue;
      }
      if (credential.holderDid != holderDid) {
        continue;
      }

      final verifier = VcVerifier(
        proofVerifier: proofVerifier,
        trustedIssuers: trustedIssuers,
        statusResolver: statusResolver,
      );
      final verification = await verifier.verifyCredentialStatus(
        credential,
        now: now,
      );
      if (!verification.isValid) {
        continue;
      }

      final unsignedVp = VpBuilder.buildUnsigned(
        credential: credential,
        holderDid: holderDid,
        nonce: nonce,
        audience: audience,
        createdAt: now,
      );
      final canonicalPayload = VpBuilder.canonicalPayload(unsignedVp);
      final proofValue = await proofSigner.signPresentation(
        unsignedPresentation: unsignedVp,
        canonicalPayload: canonicalPayload,
      );
      final vp = VpBuilder.addProof(
        unsignedPresentation: unsignedVp,
        proofValue: proofValue,
      );

      final presentationId = presentationIdFactory();
      await walletRepository.recordPresentation(
        WalletPresentation(
          presentationId: presentationId,
          credentialId: metadata.credentialId,
          verifierAudience: audience,
          nonceHash: _nonceHash(nonce),
          result: WalletPresentationResult.approved,
          createdAt: now,
        ),
      );

      return VcPresentationEnvelope(
        credentialId: metadata.credentialId,
        verifiablePresentation: vp,
      );
    }

    return null;
  }

  bool _isCandidate(WalletCredential credential, String holderDid) {
    return credential.holderDid == holderDid &&
        credential.status == WalletCredentialStatus.active &&
        credential.credentialType == 'TrisAuraHumanityCredential';
  }

  String _nonceHash(String nonce) {
    return 'sha256-${sha256.convert(utf8.encode(nonce))}';
  }
}
