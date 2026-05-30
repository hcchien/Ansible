import 'dart:convert';

import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';

import 'credential_payload_codec.dart';

class VcPresentationEnvelope {
  final String credentialId;
  final Map<String, Object?> verifiablePresentation;
  final Map<String, Object?>? nostrBinding;

  VcPresentationEnvelope({
    required this.credentialId,
    required this.verifiablePresentation,
    this.nostrBinding,
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
  final SecureCredentialPayloadCodec _codec;

  JsonCredentialPayloadDecoder({SecureCredentialPayloadCodec? codec})
    : _codec = codec ?? const SecureCredentialPayloadCodec();

  Future<Map<String, Object?>> decode(String encryptedPayload) {
    return _codec.decode(encryptedPayload);
  }
}

typedef PresentationIdFactory = String Function();

class VcPresentationService {
  static const nostrBindingKind = 27235;
  static const nostrBindingMarker = 'io.trisaura.vc.nostr-binding.v1';

  final WalletRepository walletRepository;
  final Set<String> trustedIssuers;
  final ProofVerifier proofVerifier;
  final CredentialStatusResolver statusResolver;
  final VpProofSigner proofSigner;
  final NostrEventSigner? nostrBindingSigner;
  final JsonCredentialPayloadDecoder payloadDecoder;
  final PresentationIdFactory presentationIdFactory;

  VcPresentationService({
    required this.walletRepository,
    required this.trustedIssuers,
    required this.proofVerifier,
    required this.statusResolver,
    required this.proofSigner,
    this.nostrBindingSigner,
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
    String? nostrPubkey,
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
          await payloadDecoder.decode(encryptedPayload),
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
      final nostrBinding = await _buildNostrBinding(
        vp: vp,
        holderDid: holderDid,
        nonce: nonce,
        audience: audience,
        now: now,
        nostrPubkey: nostrPubkey,
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
        nostrBinding: nostrBinding,
      );
    }

    return null;
  }

  Future<Map<String, Object?>?> _buildNostrBinding({
    required Map<String, Object?> vp,
    required String holderDid,
    required String nonce,
    required String audience,
    required DateTime now,
    required String? nostrPubkey,
  }) async {
    if (nostrPubkey == null) return null;

    final signer = nostrBindingSigner;
    if (signer == null) {
      throw StateError('Nostr binding signing is not configured.');
    }

    final vpHash = sha256
        .convert(utf8.encode(VpBuilder.canonicalPayload(vp)))
        .toString();
    final draft = NostrEventDraft(
      pubkey: nostrPubkey.toLowerCase(),
      createdAt: now.toUtc().millisecondsSinceEpoch ~/ 1000,
      kind: nostrBindingKind,
      tags: [
        ['d', nostrBindingMarker],
        ['holder', holderDid],
        ['challenge', nonce],
        ['domain', audience],
        ['vp_sha256', vpHash],
      ],
      content: '',
    );
    final event = await signer.sign(draft);
    return {'event': event.toJson()};
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
