import 'dart:convert';

import 'package:ansible_node/services/vc_presentation_service.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creates a post presentation from the first valid wallet credential',
    () async {
      final repo = InMemoryWalletRepository();
      await repo.saveCredential(
        metadata: WalletCredential(
          credentialId: 'urn:uuid:test-humanity',
          issuerDid: 'did:web:issuer.elix.cool',
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
        trustedIssuers: {'did:web:issuer.elix.cool'},
        proofVerifier: _FakeProofVerifier.valid(),
        proofSigner: _FakeVpProofSigner('holder-proof'),
        statusResolver: (_) async => CredentialStatus.active,
        presentationIdFactory: () => 'vp-test',
      );

      final envelope = await service.createForPost(
        holderDid: 'did:key:z6Mkholder',
        audience: 'https://relay.elix.cool',
        nonce: 'post-nonce',
        now: DateTime.utc(2026, 5, 5),
      );

      expect(envelope, isNotNull);
      expect(envelope!.credentialId, 'urn:uuid:test-humanity');
      expect(envelope.verifiablePresentation['holder'], 'did:key:z6Mkholder');
      expect(
        (envelope.verifiablePresentation['proof']!
            as Map<String, Object?>)['domain'],
        'https://relay.elix.cool',
      );
      expect(
        (envelope.verifiablePresentation['proof']!
            as Map<String, Object?>)['proofValue'],
        'holder-proof',
      );
      expect(_FakeVpProofSigner.lastCanonicalPayload, contains('post-nonce'));
      expect(
        _FakeVpProofSigner.lastCanonicalPayload,
        isNot(contains('holder-proof')),
      );

      final history = await repo.listPresentations('urn:uuid:test-humanity');
      expect(history.single.presentationId, 'vp-test');
      expect(history.single.result, WalletPresentationResult.approved);
      expect(history.single.verifierAudience, 'https://relay.elix.cool');
      expect(history.single.nonceHash, isNot('post-nonce'));
    },
  );

  test('selects a manifest-defined credential and required claim', () async {
    final repo = InMemoryWalletRepository();
    final credential = <String, Object?>{
      ..._humanityFixture,
      'id': 'urn:uuid:organization-member',
      'type': ['VerifiableCredential', 'OrganizationMembershipCredential'],
      'credentialSubject': {
        'id': 'did:key:z6Mkholder',
        'membershipActive': true,
      },
    };
    await repo.saveCredential(
      metadata: WalletCredential(
        credentialId: 'urn:uuid:organization-member',
        issuerDid: 'did:web:issuer.elix.cool',
        holderDid: 'did:key:z6Mkholder',
        credentialType: 'OrganizationMembershipCredential',
        status: WalletCredentialStatus.active,
        validFrom: DateTime.utc(2026, 5, 4),
        validUntil: DateTime.utc(2026, 8, 2),
        displayName: 'Organization member',
        createdAt: DateTime.utc(2026, 5, 4),
        updatedAt: DateTime.utc(2026, 5, 4),
      ),
      encryptedPayload: jsonEncode(credential),
      encryptionVersion: 'test-json',
    );
    final service = VcPresentationService(
      walletRepository: repo,
      trustedIssuers: {'did:web:issuer.elix.cool'},
      proofVerifier: _FakeProofVerifier.valid(),
      proofSigner: _FakeVpProofSigner('holder-proof'),
      statusResolver: (_) async => CredentialStatus.active,
    );

    final envelope = await service.createForVerifierRequest(
      holderDid: 'did:key:z6Mkholder',
      audience: 'https://verifier.example',
      nonce: 'nonce',
      credentialType: 'OrganizationMembershipCredential',
      requiredClaimValues: const {'membershipActive': true},
      now: DateTime.utc(2026, 5, 5),
    );

    expect(envelope?.credentialId, 'urn:uuid:organization-member');
  });

  test(
    'creates a Nostr binding event when a Nostr pubkey is supplied',
    () async {
      final repo = InMemoryWalletRepository();
      await repo.saveCredential(
        metadata: WalletCredential(
          credentialId: 'urn:uuid:test-humanity',
          issuerDid: 'did:web:issuer.elix.cool',
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
      final nostrSigner = _FakeNostrEventSigner('c' * 128);

      final service = VcPresentationService(
        walletRepository: repo,
        trustedIssuers: {'did:web:issuer.elix.cool'},
        proofVerifier: _FakeProofVerifier.valid(),
        proofSigner: _FakeVpProofSigner('holder-proof'),
        nostrBindingSigner: nostrSigner,
        statusResolver: (_) async => CredentialStatus.active,
        presentationIdFactory: () => 'vp-test',
      );

      final envelope = await service.createForPost(
        holderDid: 'did:key:z6Mkholder',
        audience: 'https://relay.elix.cool',
        nonce: 'post-nonce',
        now: DateTime.utc(2026, 5, 5, 12),
        nostrPubkey: 'b' * 64,
      );

      expect(envelope, isNotNull);
      final binding = envelope!.nostrBinding!;
      final event = binding['event']! as Map<String, Object?>;
      final tags = (event['tags']! as List).cast<List<String>>();
      final expectedVpHash = sha256
          .convert(
            utf8.encode(
              VpBuilder.canonicalPayload(envelope.verifiablePresentation),
            ),
          )
          .toString();

      expect(event['kind'], VcPresentationService.nostrBindingKind);
      expect(event['pubkey'], 'b' * 64);
      expect(
        event['created_at'],
        DateTime.utc(2026, 5, 5, 12).millisecondsSinceEpoch ~/ 1000,
      );
      expect(event['content'], '');
      expect(
        _hasTag(tags, 'd', VcPresentationService.nostrBindingMarker),
        isTrue,
      );
      expect(_hasTag(tags, 'holder', 'did:key:z6Mkholder'), isTrue);
      expect(_hasTag(tags, 'challenge', 'post-nonce'), isTrue);
      expect(_hasTag(tags, 'domain', 'https://relay.elix.cool'), isTrue);
      expect(_hasTag(tags, 'vp_sha256', expectedVpHash), isTrue);
      expect(event['id'], nostrSigner.lastDraft!.computeId());
      expect(event['sig'], 'c' * 128);
    },
  );

  test('returns null when no active humanity credential exists', () async {
    final service = VcPresentationService(
      walletRepository: InMemoryWalletRepository(),
      trustedIssuers: {'did:web:issuer.elix.cool'},
      proofVerifier: _FakeProofVerifier.valid(),
      proofSigner: _FakeVpProofSigner('holder-proof'),
      statusResolver: (_) async => CredentialStatus.active,
    );

    final envelope = await service.createForPost(
      holderDid: 'did:key:z6Mkholder',
      audience: 'https://relay.elix.cool',
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
        issuerDid: 'did:web:issuer.elix.cool',
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
      trustedIssuers: {'did:web:issuer.elix.cool'},
      proofVerifier: _FakeProofVerifier.valid(),
      proofSigner: _FakeVpProofSigner('holder-proof'),
      statusResolver: (_) async => CredentialStatus.active,
    );

    final envelope = await service.createForPost(
      holderDid: 'did:key:z6Mkother',
      audience: 'https://relay.elix.cool',
      nonce: 'post-nonce',
      now: DateTime.utc(2026, 5, 5),
    );

    expect(envelope, isNull);
    expect(await repo.listPresentations('urn:uuid:test-humanity'), isEmpty);
  });

  for (final status in [
    CredentialStatus.revoked,
    CredentialStatus.suspended,
    CredentialStatus.unknown,
  ]) {
    test('does not present $status credential status', () async {
      final repo = InMemoryWalletRepository();
      await repo.saveCredential(
        metadata: WalletCredential(
          credentialId: 'urn:uuid:test-humanity',
          issuerDid: 'did:web:issuer.elix.cool',
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
        trustedIssuers: {'did:web:issuer.elix.cool'},
        proofVerifier: _FakeProofVerifier.valid(),
        proofSigner: _FakeVpProofSigner('holder-proof'),
        statusResolver: (_) async => status,
      );

      final envelope = await service.createForPost(
        holderDid: 'did:key:z6Mkholder',
        audience: 'https://relay.elix.cool',
        nonce: 'post-nonce',
        now: DateTime.utc(2026, 5, 5),
      );

      expect(envelope, isNull);
      expect(await repo.listPresentations('urn:uuid:test-humanity'), isEmpty);
    });
  }
}

final _humanityFixture = <String, Object?>{
  '@context': [
    'https://www.w3.org/ns/credentials/v2',
    'https://elix.cool/contexts/humanity/v1',
  ],
  'id': 'urn:uuid:test-humanity',
  'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
  'issuer': 'did:web:issuer.elix.cool',
  'validFrom': '2026-05-04T00:00:00Z',
  'validUntil': '2026-08-02T00:00:00Z',
  'credentialSubject': {
    'id': 'did:key:z6Mkholder',
    'humanVerified': true,
    'assuranceLevel': 'tw_natural_person_certificate',
    'assuranceMethod': 'tw_fido_or_moica',
    'jurisdiction': 'TW',
  },
  'proof': {
    '@context': [
      'https://www.w3.org/ns/credentials/v2',
      'https://elix.cool/contexts/humanity/v1',
    ],
    'type': 'DataIntegrityProof',
    'cryptosuite': 'eddsa-jcs-2022',
    'created': '2026-05-04T10:12:00Z',
    'verificationMethod': 'did:web:issuer.elix.cool#key-1',
    'proofPurpose': 'assertionMethod',
    'proofValue': 'zissuerproof',
  },
};

bool _hasTag(List<List<String>> tags, String name, String value) {
  return tags.any(
    (tag) => tag.length >= 2 && tag[0] == name && tag[1] == value,
  );
}

class _FakeProofVerifier implements ProofVerifier {
  final bool _valid;

  _FakeProofVerifier.valid() : _valid = true;

  @override
  bool verifyCredentialProof(TrisAuraCredential credential) => _valid;
}

class _FakeVpProofSigner implements VpProofSigner {
  static String? lastCanonicalPayload;
  final String proof;

  _FakeVpProofSigner(this.proof);

  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    lastCanonicalPayload = canonicalPayload;
    expect(unsignedPresentation['proof'], isA<Map<String, Object?>>());
    return proof;
  }
}

class _FakeNostrEventSigner implements NostrEventSigner {
  final String signatureHex;
  NostrEventDraft? lastDraft;

  _FakeNostrEventSigner(this.signatureHex);

  @override
  Future<NostrEvent> sign(NostrEventDraft draft) async {
    lastDraft = draft;
    return NostrEvent(
      id: draft.computeId(),
      pubkey: draft.pubkey,
      createdAt: draft.createdAt,
      kind: draft.kind,
      tags: draft.tags,
      content: draft.content,
      sig: signatureHex,
    );
  }
}
