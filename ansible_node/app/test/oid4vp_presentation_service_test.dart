import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ansible_node/screens/wallet_verifier_consent_screen.dart';

import 'package:ansible_node/services/oid4vp_presentation_service.dart';
import 'package:ansible_node/services/oid4vp_request.dart';
import 'package:ansible_node/services/vc_presentation_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'expired consent and holder key changes never reach direct_post',
    () async {
      final repo = await _walletWithHumanityCredential();
      final signer = _BoundSigner();
      var posts = 0;
      final service = Oid4vpPresentationService(
        presentationService: VcPresentationService(
          walletRepository: repo,
          trustedIssuers: {'did:web:issuer.elix.cool'},
          proofVerifier: _FakeProofVerifier.valid(),
          statusResolver: (_) async => CredentialStatus.active,
          proofSigner: signer,
        ),
        directPostClient: Oid4vpDirectPostClient(
          client: MockClient((_) async {
            posts++;
            return http.Response('{}', 200);
          }),
        ),
      );
      final now = DateTime.utc(2026, 5, 30, 10);
      Future<PreparedOid4vpPresentation> prepare() => service.prepare(
        holderDid: 'did:key:z6Mkholder',
        request: Oid4vpAuthorizationRequest.parse(_requestUri()),
        now: now,
      );
      await expectLater(
        service.approvePrepared(
          await prepare(),
          now: now.add(const Duration(minutes: 6)),
        ),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
      final beforeRotation = await prepare();
      signer.binding = 'rotated-key';
      await expectLater(
        service.approvePrepared(beforeRotation, now: now),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
      expect(signer.calls, 0);
      final duringRotation = await prepare();
      signer.rotateWhileSigning = true;
      await expectLater(
        service.approvePrepared(duringRotation, now: now),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
      expect(signer.calls, 1);
      expect(posts, 0);
    },
  );

  test(
    'direct_post does not follow redirects beyond reviewed recipient',
    () async {
      final client = Oid4vpDirectPostClient(
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            307,
            headers: {'location': 'https://other.example/collect'},
          );
        }),
      );
      await expectLater(
        client.submit(
          request: Oid4vpAuthorizationRequest.parse(_requestUri()),
          verifiablePresentation: {},
        ),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
    },
  );

  testWidgets(
    'production consent preview includes actual extra claims; cancel never signs or sends',
    (tester) async {
      final repo = await _walletWithHumanityCredential();
      final signer = _FakeVpProofSigner('zholderproof');
      var posts = 0;
      final service = Oid4vpPresentationService(
        presentationService: VcPresentationService(
          walletRepository: repo,
          trustedIssuers: {'did:web:issuer.elix.cool'},
          proofVerifier: _FakeProofVerifier.valid(),
          statusResolver: (_) async => CredentialStatus.active,
          proofSigner: signer,
        ),
        directPostClient: Oid4vpDirectPostClient(
          client: MockClient((_) async {
            posts++;
            return http.Response('{}', 200);
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WalletVerifierConsentScreen(
            holderDid: 'did:key:z6Mkholder',
            request: Oid4vpAuthorizationRequest.parse(_requestUri()),
            presentationService: service,
            now: () => DateTime.utc(2026, 5, 30, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('actual_disclosure')),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.data?.contains('jurisdiction') ?? false),
        ),
        findsOneWidget,
      );
      expect(signer.calls, 0);
      expect(posts, 0);
      await tester.scrollUntilVisible(
        find.text('取消'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(signer.calls, 0);
      expect(posts, 0);
    },
  );

  test(
    'prepare does not sign or send; approval sends the exact reviewed credential once',
    () async {
      final repo = await _walletWithHumanityCredential();
      final signer = _FakeVpProofSigner('zholderproof');
      var posts = 0;
      Map<String, dynamic>? sent;
      final service = Oid4vpPresentationService(
        presentationService: VcPresentationService(
          walletRepository: repo,
          trustedIssuers: {'did:web:issuer.elix.cool'},
          proofVerifier: _FakeProofVerifier.valid(),
          statusResolver: (_) async => CredentialStatus.active,
          proofSigner: signer,
        ),
        directPostClient: Oid4vpDirectPostClient(
          client: MockClient((request) async {
            posts++;
            sent =
                jsonDecode(Uri.splitQueryString(request.body)['vp_token']!)
                    as Map<String, dynamic>;
            return http.Response('{}', 200);
          }),
        ),
      );
      final now = DateTime.utc(2026, 5, 30, 10);
      final prepared = await service.prepare(
        holderDid: 'did:key:z6Mkholder',
        request: Oid4vpAuthorizationRequest.parse(_requestUri()),
        now: now,
      );
      final reviewed = prepared.presentation;
      expect(jsonEncode(reviewed), contains('jurisdiction'));
      expect(posts, 0);
      expect(signer.calls, 0);
      final detached = prepared.presentation;
      (detached['verifiableCredential'] as List).clear();
      await service.approvePrepared(prepared, now: now);
      expect(sent!['verifiableCredential'], reviewed['verifiableCredential']);
      expect(posts, 1);
      expect(signer.calls, 1);
      await expectLater(
        service.approvePrepared(prepared, now: now),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
      expect(posts, 1);
    },
  );

  test(
    'revocation after consent preview prevents signing and disclosure',
    () async {
      final repo = await _walletWithHumanityCredential();
      final signer = _FakeVpProofSigner('zholderproof');
      var active = true;
      var posts = 0;
      final service = Oid4vpPresentationService(
        presentationService: VcPresentationService(
          walletRepository: repo,
          trustedIssuers: {'did:web:issuer.elix.cool'},
          proofVerifier: _FakeProofVerifier.valid(),
          statusResolver: (_) async =>
              active ? CredentialStatus.active : CredentialStatus.revoked,
          proofSigner: signer,
        ),
        directPostClient: Oid4vpDirectPostClient(
          client: MockClient((request) async {
            posts++;
            return http.Response('{}', 200);
          }),
        ),
      );
      final now = DateTime.utc(2026, 5, 30, 10);
      final prepared = await service.prepare(
        holderDid: 'did:key:z6Mkholder',
        request: Oid4vpAuthorizationRequest.parse(_requestUri()),
        now: now,
      );
      active = false;
      await expectLater(
        service.approvePrepared(prepared, now: now),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
      expect(posts, 0);
      expect(signer.calls, 0);
    },
  );

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
      trustedIssuers: {'did:web:issuer.elix.cool'},
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
      trustedIssuers: {'did:web:issuer.elix.cool'},
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

class _FakeProofVerifier implements ProofVerifier {
  final bool _valid;

  _FakeProofVerifier.valid() : _valid = true;

  @override
  bool verifyCredentialProof(TrisAuraCredential credential) => _valid;
}

class _FakeVpProofSigner implements VpProofSigner {
  int calls = 0;
  final String proof;

  _FakeVpProofSigner(this.proof);

  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    calls++;
    expect(canonicalPayload, contains('nonce-123'));
    expect(canonicalPayload, isNot(contains(proof)));
    return proof;
  }
}

class _BoundSigner extends _FakeVpProofSigner
    implements ConfiguredVpProofSigner {
  _BoundSigner() : super('zholderproof');
  String binding = 'initial-key';
  bool rotateWhileSigning = false;
  @override
  Future<String> identityBinding(String holderDid) async => binding;
  @override
  Future<Map<String, Object?>> proofOptions(String holderDid) async => {};
  @override
  Future<String> signPresentation({
    required Map<String, Object?> unsignedPresentation,
    required String canonicalPayload,
  }) async {
    final proof = await super.signPresentation(
      unsignedPresentation: unsignedPresentation,
      canonicalPayload: canonicalPayload,
    );
    if (rotateWhileSigning) binding = 'next-key';
    return proof;
  }
}
