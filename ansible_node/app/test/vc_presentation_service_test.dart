import 'dart:convert';

import 'package:ansible_node/services/vc_presentation_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creates a post presentation from the first valid wallet credential',
    () async {
      final repo = InMemoryWalletRepository();
      await repo.saveCredential(
        metadata: WalletCredential(
          credentialId: 'urn:uuid:test-humanity',
          issuerDid: 'did:web:issuer.trisaura.io',
          holderDid: 'did:key:z6Mkholder',
          credentialType: 'TrisAuraHumanityCredential',
          status: WalletCredentialStatus.active,
          validFrom: DateTime.utc(2026, 5, 4),
          validUntil: DateTime.utc(2026, 8, 2),
          displayName: 'Verified Human',
          createdAt: DateTime.utc(2026, 5, 4),
          updatedAt: DateTime.utc(2026, 5, 4),
        ),
        encryptedPayload: jsonEncode(_humanityFixture),
        encryptionVersion: 'test-json',
      );

      final service = VcPresentationService(
        walletRepository: repo,
        trustedIssuers: {'did:web:issuer.trisaura.io'},
        proofVerifier: _FakeProofVerifier.valid(),
        proofSigner: _FakeVpProofSigner('holder-proof'),
        presentationIdFactory: () => 'vp-test',
      );

      final envelope = await service.createForPost(
        holderDid: 'did:key:z6Mkholder',
        audience: 'https://relay.trisaura.io',
        nonce: 'post-nonce',
        now: DateTime.utc(2026, 5, 5),
      );

      expect(envelope, isNotNull);
      expect(envelope!.credentialId, 'urn:uuid:test-humanity');
      expect(envelope.verifiablePresentation['holder'], 'did:key:z6Mkholder');
      expect(
        (envelope.verifiablePresentation['proof']!
            as Map<String, Object?>)['domain'],
        'https://relay.trisaura.io',
      );
      expect(
        (envelope.verifiablePresentation['proof']!
            as Map<String, Object?>)['proofValue'],
        'holder-proof',
      );

      final history = await repo.listPresentations('urn:uuid:test-humanity');
      expect(history.single.presentationId, 'vp-test');
      expect(history.single.result, WalletPresentationResult.approved);
      expect(history.single.verifierAudience, 'https://relay.trisaura.io');
      expect(history.single.nonceHash, isNot('post-nonce'));
    },
  );

  test('returns null when no active humanity credential exists', () async {
    final service = VcPresentationService(
      walletRepository: InMemoryWalletRepository(),
      trustedIssuers: {'did:web:issuer.trisaura.io'},
      proofVerifier: _FakeProofVerifier.valid(),
      proofSigner: _FakeVpProofSigner('holder-proof'),
    );

    final envelope = await service.createForPost(
      holderDid: 'did:key:z6Mkholder',
      audience: 'https://relay.trisaura.io',
      nonce: 'post-nonce',
      now: DateTime.utc(2026, 5, 5),
    );

    expect(envelope, isNull);
  });

  test('does not present a credential for a different holder DID', () async {
    final repo = InMemoryWalletRepository();
    await repo.saveCredential(
      metadata: WalletCredential(
        credentialId: 'urn:uuid:test-humanity',
        issuerDid: 'did:web:issuer.trisaura.io',
        holderDid: 'did:key:z6Mkholder',
        credentialType: 'TrisAuraHumanityCredential',
        status: WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 4),
        validUntil: DateTime.utc(2026, 8, 2),
        displayName: 'Verified Human',
        createdAt: DateTime.utc(2026, 5, 4),
        updatedAt: DateTime.utc(2026, 5, 4),
      ),
      encryptedPayload: jsonEncode(_humanityFixture),
      encryptionVersion: 'test-json',
    );

    final service = VcPresentationService(
      walletRepository: repo,
      trustedIssuers: {'did:web:issuer.trisaura.io'},
      proofVerifier: _FakeProofVerifier.valid(),
      proofSigner: _FakeVpProofSigner('holder-proof'),
    );

    final envelope = await service.createForPost(
      holderDid: 'did:key:z6Mkother',
      audience: 'https://relay.trisaura.io',
      nonce: 'post-nonce',
      now: DateTime.utc(2026, 5, 5),
    );

    expect(envelope, isNull);
    expect(await repo.listPresentations('urn:uuid:test-humanity'), isEmpty);
  });
}

final _humanityFixture = <String, Object?>{
  '@context': [
    'https://www.w3.org/ns/credentials/v2',
    'https://trisaura.io/contexts/humanity/v1',
  ],
  'id': 'urn:uuid:test-humanity',
  'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
  'issuer': 'did:web:issuer.trisaura.io',
  'validFrom': '2026-05-04T00:00:00Z',
  'validUntil': '2026-08-02T00:00:00Z',
  'credentialSubject': {
    'id': 'did:key:z6Mkholder',
    'humanVerified': true,
    'assuranceLevel': 'tw_natural_person_certificate',
    'assuranceMethod': 'tw_fido_or_moica',
    'jurisdiction': 'TW',
  },
  'proof': {'proofValue': 'issuer-proof'},
};

class _FakeProofVerifier implements ProofVerifier {
  final bool _valid;

  _FakeProofVerifier.valid() : _valid = true;

  @override
  bool verifyCredentialProof(TrisAuraCredential credential) => _valid;
}

class _FakeVpProofSigner implements VpProofSigner {
  final String proof;

  _FakeVpProofSigner(this.proof);

  @override
  Future<String> signPresentation({
    required TrisAuraCredential credential,
    required String holderDid,
    required String nonce,
    required String audience,
  }) async {
    return proof;
  }
}
