import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';

import 'atproto_client.dart';
import 'oid4vp_presentation_service.dart';
import 'public_profile_credential_preferences.dart';
import 'vc_presentation_service.dart';

typedef PublicProfileCredentialClientFactory =
    AtProtoClient Function(String baseUrl);

class PublicProfileCredentialPresentationService {
  PublicProfileCredentialPresentationService({
    required WalletRepository walletRepository,
    required PublicProfileCredentialPreferenceStore preferenceStore,
    required DidSigner didSigner,
    PublicProfileCredentialClientFactory? clientFactory,
  }) : _wallet = walletRepository,
       _preferences = preferenceStore,
       _signer = didSigner,
       _clientFactory =
           clientFactory ?? ((baseUrl) => AtProtoClient(baseUrl: baseUrl));

  final WalletRepository _wallet;
  final PublicProfileCredentialPreferenceStore _preferences;
  final DidSigner _signer;
  final PublicProfileCredentialClientFactory _clientFactory;

  Future<List<String>> presentSelected({
    required String holderDid,
    required RemoteNode node,
    DateTime? now,
  }) async {
    final selected = await _preferences.selectedCredentialIds(holderDid);
    if (selected.isEmpty) return const <String>[];

    final credentials = await _wallet.listCredentials();
    final presentedTypes = <String>[];
    final instant = (now ?? DateTime.now()).toUtc();

    for (final credential in credentials) {
      if (!selected.contains(credential.credentialId) ||
          credential.status != WalletCredentialStatus.active ||
          !credential.validUntil.isAfter(instant) ||
          !isPublicProfileCredentialType(credential.credentialType)) {
        continue;
      }

      final envelope =
          await VcPresentationService(
            walletRepository: _wallet,
            trustedIssuers: {credential.issuerDid},
            proofVerifier: const SyntacticDataIntegrityProofVerifier(),
            statusResolver: (_) async => CredentialStatus.active,
            proofSigner: _PublicProfileVpProofSigner(_signer),
          ).createForVerifierRequest(
            holderDid: holderDid,
            audience: node.url,
            nonce:
                'profile-${instant.microsecondsSinceEpoch}-${credential.credentialType}',
            credentialType: credential.credentialType,
            credentialId: credential.credentialId,
            now: instant,
          );
      if (envelope == null) {
        throw StateError('public_profile_credential_unavailable');
      }

      await _clientFactory(node.url).presentPublicProfileCredential(
        holderDid: holderDid,
        vp: envelope.verifiablePresentation.cast<String, dynamic>(),
      );
      presentedTypes.add(credential.credentialType);
    }

    return presentedTypes.toSet().toList()..sort();
  }
}

class _PublicProfileVpProofSigner implements VpProofSigner {
  const _PublicProfileVpProofSigner(this._signer);

  final DidSigner _signer;

  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    final signature = await _signer.sign(utf8.encode(canonicalPayload));
    return signature.hex;
  }
}
