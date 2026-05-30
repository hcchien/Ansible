import 'dart:convert';

import 'package:ansible_node/services/oid4vp_presentation_service.dart';
import 'package:ansible_node/services/oid4vp_request.dart';
import 'package:ansible_node/services/vc_presentation_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('encodes Ed25519 signature hex as multibase base58-btc proofValue', () {
    expect(
      dataIntegrityProofValueFromEd25519SignatureHex('00' * 64),
      'z${'1' * 64}',
    );
  });

  test('posts vp_token and presentation_submission to response_uri', () async {
    final repo = await _walletWithHumanityCredential();
    http.Request? captured;
    final directPostClient = Oid4vpDirectPostClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      }),
    );
    final presentationService = VcPresentationService(
      walletRepository: repo,
      trustedIssuers: {'did:web:issuer.trisaura.io'},
      proofVerifier: _FakeProofVerifier.valid(),
      statusResolver: (_) async => CredentialStatus.active,
      proofSigner: _FakeVpProofSigner('zholderproof'),
      presentationIdFactory: () => 'vp-oid4vp',
    );
    final service = Oid4vpPresentationService(
      presentationService: presentationService,
      directPostClient: directPostClient,
    );
    final request = Oid4vpAuthorizationRequest.parse(_requestUri());

    final result = await service.approve(
      holderDid: 'did:key:z6Mkholder',
      request: request,
      now: DateTime.utc(2026, 5, 30, 10),
    );

    expect(result.credentialId, 'urn:uuid:test-humanity');
    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.toString(), 'https://verifier.example/direct_post');
    expect(
      captured!.headers['content-type'],
      contains('application/x-www-form-urlencoded'),
    );

    final body = Uri.splitQueryString(captured!.body);
    expect(body['state'], 'state-abc');

    final vp = jsonDecode(body['vp_token']!) as Map<String, dynamic>;
    expect(vp['holder'], 'did:key:z6Mkholder');
    expect((vp['proof'] as Map<String, dynamic>)['challenge'], 'nonce-123');
    expect(
      (vp['proof'] as Map<String, dynamic>)['domain'],
      'https://verifier.example',
    );
    expect(jsonEncode(vp), isNot(contains('nationalId')));

    final submission =
        jsonDecode(body['presentation_submission']!) as Map<String, dynamic>;
    expect(submission['definition_id'], 'pd-humanity');
    expect(
      ((submission['descriptor_map'] as List).single
          as Map<String, dynamic>)['id'],
      'humanity-vc',
    );

    final history = await repo.listPresentations('urn:uuid:test-humanity');
    expect(history.single.result, WalletPresentationResult.approved);
    expect(history.single.verifierAudience, 'https://verifier.example');
  });

  test('records failed presentation when verifier direct_post fails', () async {
    final repo = await _walletWithHumanityCredential();
    final directPostClient = Oid4vpDirectPostClient(
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    final presentationService = VcPresentationService(
      walletRepository: repo,
      trustedIssuers: {'did:web:issuer.trisaura.io'},
      proofVerifier: _FakeProofVerifier.valid(),
      statusResolver: (_) async => CredentialStatus.active,
      proofSigner: _FakeVpProofSigner('zholderproof'),
      presentationIdFactory: () => 'vp-oid4vp',
    );
    final service = Oid4vpPresentationService(
      presentationService: presentationService,
      directPostClient: directPostClient,
    );
    final request = Oid4vpAuthorizationRequest.parse(_requestUri());

    await expectLater(
      service.approve(
        holderDid: 'did:key:z6Mkholder',
        request: request,
        now: DateTime.utc(2026, 5, 30, 10),
      ),
      throwsA(isA<Oid4vpSubmissionException>()),
    );

    final history = await repo.listPresentations('urn:uuid:test-humanity');
    expect(history.single.result, WalletPresentationResult.failed);
    expect(history.single.verifierAudience, 'https://verifier.example');
  });
}

Future<InMemoryWalletRepository> _walletWithHumanityCredential() async {
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
  return repo;
}

String _requestUri() {
  final definition = {
    'id': 'pd-humanity',
    'input_descriptors': [
      {
        'id': 'humanity-vc',
        'constraints': {
          'fields': [
            {
              'path': [r'$.type'],
              'filter': {
                'type': 'array',
                'contains': {'const': 'TrisAuraHumanityCredential'},
              },
            },
          ],
        },
      },
    ],
  };

  return Uri(
    scheme: 'openid4vp',
    host: 'authorize',
    queryParameters: {
      'client_id': 'https://verifier.example',
      'response_type': 'vp_token',
      'response_mode': 'direct_post',
      'response_uri': 'https://verifier.example/direct_post',
      'nonce': 'nonce-123',
      'state': 'state-abc',
      'presentation_definition': jsonEncode(definition),
    },
  ).toString();
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
  'proof': {
    '@context': [
      'https://www.w3.org/ns/credentials/v2',
      'https://trisaura.io/contexts/humanity/v1',
    ],
    'type': 'DataIntegrityProof',
    'cryptosuite': 'eddsa-jcs-2022',
    'created': '2026-05-04T10:12:00Z',
    'verificationMethod': 'did:web:issuer.trisaura.io#key-1',
    'proofPurpose': 'assertionMethod',
    'proofValue': 'zissuerproof',
  },
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
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    expect(canonicalPayload, contains('nonce-123'));
    expect(canonicalPayload, isNot(contains(proof)));
    return proof;
  }
}
