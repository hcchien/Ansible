import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_node/services/oid4vci_wallet_client.dart';
import 'package:ansible_node/services/wallet_holder_key_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses a single-use hosted credential offer', () {
    final offer = Oid4vciCredentialOffer.parse({
      'credential_issuer': 'https://issuer-dev.elix.cool/tenants/ntp',
      'credential_configuration_ids': ['PoliticalPartyMembershipCredential-v1'],
      'forum_host_id': 'host-local-dev',
      'board_id': 'board-ntp-members',
      'grants': {
        'urn:ietf:params:oauth:grant-type:pre-authorized_code': {
          'pre-authorized_code': 'eix_offer_v1_secret',
        },
      },
    });

    expect(offer.credentialIssuer.host, 'issuer-dev.elix.cool');
    expect(offer.configurationId, 'PoliticalPartyMembershipCredential-v1');
    expect(offer.preAuthorizedCode, 'eix_offer_v1_secret');
    expect(offer.forumHostId, 'host-local-dev');
    expect(offer.boardId, 'board-ntp-members');
  });

  test('rejects non-HTTPS and ambiguous credential offers', () {
    expect(
      () => Oid4vciCredentialOffer.parse({
        'credential_issuer': 'http://issuer.example/tenants/ntp',
        'credential_configuration_ids': ['a', 'b'],
        'forum_host_id': 'host-local-dev',
        'board_id': 'board-ntp-members',
        'grants': {
          'urn:ietf:params:oauth:grant-type:pre-authorized_code': {
            'pre-authorized_code': 'secret',
          },
        },
      }),
      throwsA(isA<Oid4vciWalletException>()),
    );
  });

  test('converts ASN.1 ECDSA signatures to fixed-width JOSE format', () {
    final der = <int>[
      0x30,
      0x46,
      0x02,
      0x21,
      0x00,
      ...List<int>.filled(32, 0x80),
      0x02,
      0x21,
      0x00,
      ...List<int>.filled(32, 0x81),
    ];
    final jose = ecdsaDerSignatureToJose(der);
    expect(jose, hasLength(64));
    expect(jose.take(32), everyElement(0x80));
    expect(jose.skip(32), everyElement(0x81));
  });

  test('wallet credential wrapper preserves compact JWT for OID4VP', () {
    final credential = TrisAuraCredential.fromJson({
      'format': 'jwt_vc_json',
      'compact': 'header.payload.signature',
      'board_id': 'board-ntp-members',
      'vc': {
        '@context': ['https://www.w3.org/2018/credentials/v1'],
        'id': 'https://issuer.example/credentials/1',
        'type': ['VerifiableCredential', 'PoliticalPartyMembershipCredential'],
        'issuer': 'did:elix:org:ntp',
        'validFrom': '2026-07-22T00:00:00Z',
        'validUntil': '2026-10-20T00:00:00Z',
        'credentialSubject': {
          'id': 'did:jwk:holder',
          'organization_id': 'did:elix:org:ntp',
          'membership': true,
          'forum_host_id': 'host-local-dev',
          'board_id': 'board-ntp-members',
        },
      },
    });

    expect(credential.compactJwt, 'header.payload.signature');
    expect(credential.hasType('PoliticalPartyMembershipCredential'), isTrue);
  });

  test('pairwise did:jwk uses deterministic RFC 7638 member order', () async {
    final signer = HardwareHolderJwtSigner(key: _FakeHolderKey());
    final did = await signer.pairwiseDid();
    final encoded = did.substring('did:jwk:'.length);
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));

    expect(
      decoded,
      '{"crv":"P-256","kty":"EC","x":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","y":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}',
    );
  });

  test(
    'membership application is nonce-bound to the hardware holder key',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = Oid4vciWalletClient(
        walletRepository: _FakeWalletRepository(),
        holderKey: _FakeHolderKey(),
        now: () => DateTime.utc(2026, 7, 22, 12),
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (request.url.path.endsWith('/nonce')) {
            return http.Response(jsonEncode({'c_nonce': 'nonce-1'}), 200);
          }
          expect(request.url.path, '/tenants/party/issuance-requests');
          final body = bodies.last;
          expect(body['holder_pairwise_did'], startsWith('did:jwk:'));
          expect(body['membership_class'], 'member');
          expect(body['forum_host_id'], 'host-local-dev');
          expect(body['board_id'], 'board-ntp-members');
          expect((body['proof_jwt'] as String).split('.'), hasLength(3));
          return http.Response(
            jsonEncode({
              'request': {'id': 'issuance-1'},
            }),
            201,
          );
        }),
      );

      final id = await client.applyForMembership(
        credentialIssuer: Uri.parse('https://issuer.example/tenants/party'),
        forumHostId: 'host-local-dev',
        boardId: 'board-ntp-members',
      );

      expect(id, 'issuance-1');
      expect(bodies, hasLength(2));
    },
  );
}

class _FakeWalletRepository implements WalletRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHolderKey implements HolderBindingKey {
  @override
  Future<IdentityPublicKey> ensureKey() async => const IdentityPublicKey(
    algorithm: IdentityKeyAlgorithm.p256Sha256,
    publicKeyHex:
        '04'
        '0000000000000000000000000000000000000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000000',
    custody: IdentityKeyCustody.hardware,
  );

  @override
  Future<IdentitySignature> sign(
    List<int> message, {
    bool reuseAuthenticationContext = false,
  }) async => IdentitySignature(
    algorithm: IdentityKeyAlgorithm.p256Sha256,
    hex: '30440220${'01' * 32}0220${'02' * 32}',
  );
}
