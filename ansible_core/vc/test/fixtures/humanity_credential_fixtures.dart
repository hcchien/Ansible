import 'package:ansible_vc/ansible_vc.dart';

final humanityFixture = <String, Object?>{
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
  'credentialStatus': {
    'id': 'https://issuer.elix.cool/status/humanity/2026-05#test',
    'type': 'TrisAuraStatusList2026',
    'statusPurpose': 'revocation',
  },
  'proof': {
    'type': 'DataIntegrityProof',
    'cryptosuite': 'eddsa-jcs-2022',
    'verificationMethod': 'did:web:issuer.elix.cool#key-2026-05',
    'created': '2026-05-04T10:12:00Z',
    'proofPurpose': 'assertionMethod',
    'proofValue': 'test-proof',
  },
};

final expiredHumanityFixture = <String, Object?>{
  ...humanityFixture,
  'id': 'urn:uuid:expired-humanity',
  'validUntil': '2026-06-01T00:00:00Z',
};

class FakeProofVerifier implements ProofVerifier {
  final bool _valid;

  FakeProofVerifier.valid() : _valid = true;

  FakeProofVerifier.invalid() : _valid = false;

  @override
  bool verifyCredentialProof(TrisAuraCredential credential) => _valid;
}
