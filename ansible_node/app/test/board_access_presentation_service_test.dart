import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/board_access_presentation_service.dart';
import 'package:ansible_node/services/oid4vci_wallet_client.dart';
import 'package:ansible_node/services/wallet_holder_key_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('hardware holder JWT binds a canonical P-256 JWK', () async {
    final key = _FakeHolderKey();
    final signer = HardwareHolderJwtSigner(key: key);
    final compact = await signer.signJwt(
      typ: 'openid4vp+jwt',
      claims: {'aud': 'https://relay.example', 'nonce': 'n', 'iat': 1},
    );

    final parts = compact.split('.');
    expect(parts, hasLength(3));
    final header =
        jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts.first))),
            )
            as Map<String, dynamic>;
    expect(header['alg'], 'ES256');
    expect(header['typ'], 'openid4vp+jwt');
    expect(header['jwk']['kty'], 'EC');
    expect(base64Url.decode(base64Url.normalize(parts.last)), hasLength(64));
  });

  test(
    'proof headers bind method path board scope nonce and token hash',
    () async {
      final key = _FakeHolderKey();
      final service = BoardAccessPresentationService(
        walletRepository: InMemoryWalletRepository(),
        holderKey: key,
        now: () => DateTime.utc(2026, 7, 22, 10),
      );
      final headers = await service.proofHeaders(
        capability: BoardAccessCapability(
          token: 'elix_board_v1_secret',
          forumHostId: 'host-local-dev',
          boardId: 'members',
          host: Uri.parse('https://relay.example'),
          scopes: const ['read'],
          expiresAt: DateTime.utc(2026, 7, 22, 10, 5),
          policyVersion: 3,
        ),
        method: 'get',
        requestUri: Uri.parse(
          'https://relay.example/api/v1/forum-host/boards/members/ops/delta',
        ),
        scope: 'read',
      );

      expect(headers['x-elix-board-capability'], 'elix_board_v1_secret');
      expect(headers['x-elix-board-jwk'], isNotEmpty);
      expect(
        key.lastMessage,
        startsWith(
          'GET\n/api/v1/forum-host/boards/members/ops/delta\nmembers\nread\n',
        ),
      );
      expect(headers['x-elix-board-proof'], key.signature.hex);
    },
  );

  test('a credential issued for one host cannot authorize another', () async {
    final key = _FakeHolderKey();
    final holder = await HardwareHolderJwtSigner(key: key).pairwiseDid();
    final now = DateTime.utc(2026, 7, 22, 10);
    final wallet = InMemoryWalletRepository();
    await wallet.saveCredential(
      metadata: WalletCredential(
        credentialId: 'credential-a',
        issuerDid: 'did:elix:org:party',
        holderDid: holder,
        credentialType: 'PoliticalPartyMembershipCredential',
        status: WalletCredentialStatus.active,
        validFrom: now.subtract(const Duration(minutes: 1)),
        validUntil: now.add(const Duration(days: 30)),
        displayName: 'Membership',
        createdAt: now,
        updatedAt: now,
      ),
      encryptedPayload: jsonEncode({
        'format': 'jwt_vc_json',
        'compact': 'header.payload.signature',
        'forum_host_id': 'host-local-dev',
        'board_id': 'board-a',
        'vc': {
          'type': [
            'VerifiableCredential',
            'PoliticalPartyMembershipCredential',
          ],
          'issuer': 'did:elix:org:party',
          'credentialSubject': {
            'id': holder,
            'membership': true,
            'forum_host_id': 'host-local-dev',
            'board_id': 'board-a',
          },
        },
      }),
      encryptionVersion: 'test-json',
    );
    final service = BoardAccessPresentationService(
      walletRepository: wallet,
      holderKey: key,
      now: () => now,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/access-requirements')) {
          return http.Response(
            jsonEncode({
              'host': 'https://relay.example',
              'forum_host_id': 'another-host',
              'board_id': 'board-a',
              'policy': {
                'read': {'requirement': 'member'},
                'requirements': {
                  'member': {
                    'credential_type': 'PoliticalPartyMembershipCredential',
                    'trusted_issuers': ['did:elix:org:party'],
                    'claims': [
                      {'path': 'membership', 'op': 'equals', 'value': true},
                    ],
                  },
                },
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'nonce': 'n', 'state': 's'}), 200);
      }),
    );

    await expectLater(
      service.authorize(
        forumHost: Uri.parse('https://relay.example'),
        boardId: 'board-a',
        action: 'read',
      ),
      throwsA(
        isA<BoardAccessException>().having(
          (error) => error.code,
          'code',
          'no_matching_credential',
        ),
      ),
    );
  });

  test(
    'Taiwan citizenship VC is presented with a device-bound JCS VP',
    () async {
      final key = _FakeHolderKey();
      final now = DateTime.utc(2026, 7, 24, 10);
      final wallet = InMemoryWalletRepository();
      await wallet.saveCredential(
        metadata: WalletCredential(
          credentialId: 'tw-citizen',
          issuerDid: 'did:web:issuer-dev.elix.cool',
          holderDid: 'did:plc:citizen',
          credentialType: 'TaiwanCitizenshipCredential',
          status: WalletCredentialStatus.active,
          validFrom: now.subtract(const Duration(minutes: 1)),
          validUntil: now.add(const Duration(days: 30)),
          displayName: 'Taiwan Citizenship',
          createdAt: now,
          updatedAt: now,
        ),
        encryptedPayload: jsonEncode({
          '@context': ['https://www.w3.org/ns/credentials/v2'],
          'id': 'urn:uuid:tw-citizen',
          'type': ['VerifiableCredential', 'TaiwanCitizenshipCredential'],
          'issuer': 'did:web:issuer-dev.elix.cool',
          'validFrom': now
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
          'validUntil': now.add(const Duration(days: 30)).toIso8601String(),
          'credentialSubject': {
            'id': 'did:plc:citizen',
            'citizenshipVerified': true,
          },
          'proof': {
            'type': 'DataIntegrityProof',
            'cryptosuite': 'eddsa-jcs-2022',
            'proofValue': 'zissuer-proof',
          },
        }),
        encryptionVersion: 'test-json',
      );

      Map<String, dynamic>? presented;
      final service = BoardAccessPresentationService(
        walletRepository: wallet,
        holderKey: key,
        didSigner: _RecordingDidSigner(),
        now: () => now,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/access-requirements')) {
            return http.Response(
              jsonEncode({
                'host': 'https://relay.example',
                'forum_host_id': 'host-local-dev',
                'board_id': 'taiwan',
                'policy': {
                  'post': {'requirement': 'member'},
                  'requirements': {
                    'member': {
                      'credential_type': 'TaiwanCitizenshipCredential',
                      'trusted_issuers': ['did:web:issuer-dev.elix.cool'],
                      'claims': [
                        {
                          'path': 'citizenshipVerified',
                          'op': 'equals',
                          'value': true,
                        },
                      ],
                    },
                  },
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/presentation/options')) {
            return http.Response(
              jsonEncode({'nonce': 'nonce-1', 'state': 'state-1'}),
              200,
            );
          }
          presented = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'board_capability': 'elix_board_v1_test',
              'expires_at': now
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
              'scopes': ['post'],
              'policy_version': 1,
            }),
            200,
          );
        }),
      );

      final capability = await service.authorize(
        forumHost: Uri.parse('https://relay.example'),
        boardId: 'taiwan',
        action: 'post',
      );

      expect(capability.scopes, ['post']);
      final vp = presented?['vp_token'] as Map<String, dynamic>;
      expect(vp['holder'], 'did:plc:citizen');
      expect(vp['deviceKeyJwk']['kty'], 'EC');
      expect(vp['proof']['challenge'], 'nonce-1');
      expect(
        vp['verifiableCredential'][0]['type'],
        contains('TaiwanCitizenshipCredential'),
      );
    },
  );

  test(
    'legacy board slug continues capability exchange on canonical id',
    () async {
      final key = _FakeHolderKey();
      final now = DateTime.utc(2026, 7, 24, 10);
      final wallet = InMemoryWalletRepository();
      await wallet.saveCredential(
        metadata: WalletCredential(
          credentialId: 'tw-citizen',
          issuerDid: 'did:web:issuer-dev.elix.cool',
          holderDid: 'did:plc:citizen',
          credentialType: 'TaiwanCitizenshipCredential',
          status: WalletCredentialStatus.active,
          validFrom: now.subtract(const Duration(minutes: 1)),
          validUntil: now.add(const Duration(days: 30)),
          displayName: 'Taiwan Citizenship',
          createdAt: now,
          updatedAt: now,
        ),
        encryptedPayload: jsonEncode(_citizenshipVc(now)),
        encryptionVersion: 'test-json',
      );
      final requestedPaths = <String>[];
      final service = BoardAccessPresentationService(
        walletRepository: wallet,
        holderKey: key,
        didSigner: _RecordingDidSigner(),
        now: () => now,
        httpClient: MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path.endsWith('/access-requirements')) {
            return http.Response(
              jsonEncode({
                'host': 'https://relay.example',
                'forum_host_id': 'host-local-dev',
                'board_id': '2',
                'policy': {
                  'post': {'requirement': 'member'},
                  'requirements': {
                    'member': {
                      'credential_type': 'TaiwanCitizenshipCredential',
                      'trusted_issuers': ['did:web:issuer-dev.elix.cool'],
                      'claims': [
                        {
                          'path': 'citizenshipVerified',
                          'op': 'equals',
                          'value': true,
                        },
                      ],
                    },
                  },
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/presentation/options')) {
            return http.Response(jsonEncode({'nonce': 'n', 'state': 's'}), 200);
          }
          return http.Response(
            jsonEncode({
              'board_capability': 'capability',
              'expires_at': now
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
              'scopes': ['post'],
              'policy_version': 1,
            }),
            200,
          );
        }),
      );

      final capability = await service.authorize(
        forumHost: Uri.parse('https://relay.example'),
        boardId: '2026',
        action: 'post',
      );

      expect(capability.boardId, '2');
      expect(
        requestedPaths,
        contains('/api/v1/forum-host/boards/2/presentation/options'),
      );
      expect(
        requestedPaths,
        contains('/api/v1/forum-host/boards/2/presentation/verify'),
      );
    },
  );
}

Map<String, Object?> _citizenshipVc(DateTime now) => {
  '@context': ['https://www.w3.org/ns/credentials/v2'],
  'id': 'urn:uuid:tw-citizen',
  'type': ['VerifiableCredential', 'TaiwanCitizenshipCredential'],
  'issuer': 'did:web:issuer-dev.elix.cool',
  'validFrom': now.subtract(const Duration(minutes: 1)).toIso8601String(),
  'validUntil': now.add(const Duration(days: 30)).toIso8601String(),
  'credentialSubject': {'id': 'did:plc:citizen', 'citizenshipVerified': true},
  'proof': {
    'type': 'DataIntegrityProof',
    'cryptosuite': 'eddsa-jcs-2022',
    'proofValue': 'zissuer-proof',
  },
};

class _FakeHolderKey implements HolderBindingKey {
  final signature = IdentitySignature(
    algorithm: IdentityKeyAlgorithm.p256Sha256,
    hex: _derSignatureHex(),
  );
  String? lastMessage;

  @override
  Future<IdentityPublicKey> ensureKey() async => IdentityPublicKey(
    algorithm: IdentityKeyAlgorithm.p256Sha256,
    publicKeyHex: '04${'11' * 32}${'22' * 32}',
    custody: IdentityKeyCustody.hardware,
    hardwareSecurityLevel: 'secure_enclave',
  );

  @override
  Future<IdentitySignature> sign(List<int> message) async {
    lastMessage = utf8.decode(message);
    return signature;
  }

  static String _derSignatureHex() => [
    0x30,
    0x44,
    0x02,
    0x20,
    ...List<int>.filled(32, 1),
    0x02,
    0x20,
    ...List<int>.filled(32, 2),
  ].map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

class _RecordingDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return Ed25519Signature('11' * 64);
  }
}
