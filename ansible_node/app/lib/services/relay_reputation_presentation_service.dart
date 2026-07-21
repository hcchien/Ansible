import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';

import '../config/app_environment.dart';
import 'atproto_client.dart';
import 'oid4vp_presentation_service.dart';
import 'vc_presentation_service.dart';

typedef RelayPresentationBuilder =
    Future<VcPresentationEnvelope?> Function({
      required String holderDid,
      required String audience,
      required String nonce,
      required DateTime now,
    });

typedef AtProtoClientFactory = AtProtoClient Function(String baseUrl);

class RelayReputationPresentationResult {
  const RelayReputationPresentationResult({
    required this.presented,
    required this.tier,
  });

  final bool presented;
  final String? tier;
}

/// Presents an active locally-held Humanity VC to a Relay before outbound
/// sync. The Relay remains authoritative: it verifies both the holder proof
/// and issuer proof before deriving the reputation tier.
class RelayReputationPresentationService {
  RelayReputationPresentationService({
    required WalletRepository walletRepository,
    required DidReputationRepository reputationRepository,
    DidSigner? didSigner,
    RelayPresentationBuilder? presentationBuilder,
    AtProtoClientFactory? clientFactory,
  }) : _walletRepository = walletRepository,
       _reputationRepository = reputationRepository,
       _didSigner = didSigner ?? DidSignerImpl(),
       _presentationBuilder = presentationBuilder,
       _clientFactory = clientFactory ?? ((url) => AtProtoClient(baseUrl: url));

  final WalletRepository _walletRepository;
  final DidReputationRepository _reputationRepository;
  final DidSigner _didSigner;
  final RelayPresentationBuilder? _presentationBuilder;
  final AtProtoClientFactory _clientFactory;

  Future<RelayReputationPresentationResult> present({
    required String holderDid,
    required RemoteNode node,
    DateTime? now,
  }) async {
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final envelope = await (_presentationBuilder ?? _createPresentation)(
      holderDid: holderDid,
      audience: node.url,
      nonce: 'sync-${issuedAt.microsecondsSinceEpoch}',
      now: issuedAt,
    );
    if (envelope == null) {
      return const RelayReputationPresentationResult(
        presented: false,
        tier: null,
      );
    }

    final tier = await _clientFactory(node.url).presentVp(
      holderDid: holderDid,
      vp: envelope.verifiablePresentation.cast<String, dynamic>(),
      nostrBinding: envelope.nostrBinding?.cast<String, dynamic>(),
    );
    await _reputationRepository.put(holderDid, tier, updatedAt: issuedAt);
    return RelayReputationPresentationResult(presented: true, tier: tier);
  }

  String _issuerDid() {
    final host = Uri.parse(AppEnvironment.issuerBaseUrl).host;
    return 'did:web:$host';
  }

  Future<VcPresentationEnvelope?> _createPresentation({
    required String holderDid,
    required String audience,
    required String nonce,
    required DateTime now,
  }) {
    return VcPresentationService(
      walletRepository: _walletRepository,
      trustedIssuers: {_issuerDid()},
      proofVerifier: const SyntacticDataIntegrityProofVerifier(),
      // The Relay performs the authoritative online credential verification.
      // Local metadata already fails closed for revoked/expired credentials.
      statusResolver: (_) async => CredentialStatus.active,
      proofSigner: _RelayVpProofSigner(_didSigner),
    ).createForPost(
      holderDid: holderDid,
      audience: audience,
      nonce: nonce,
      now: now,
    );
  }
}

class _RelayVpProofSigner implements VpProofSigner {
  const _RelayVpProofSigner(this._signer);

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
