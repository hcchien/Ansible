import 'dart:convert';
import 'dart:math';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/hosted_issuer_admin_client.dart';
import 'package:ansible_node/services/sync_capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'bootstrap binds a purpose-specific hardware root key signature',
    () async {
      late Map<String, dynamic> request;
      final key = _FakeRootKey();
      final client = HostedIssuerAdminClient(
        baseUrl: 'https://issuer.example',
        ownerDid: 'did:elix:admin:alice',
        rootKey: key,
        webAuthn: _FakeWebAuthn(),
        now: () => DateTime.utc(2026, 7, 22, 10),
        random: Random(1),
        client: MockClient((incoming) async {
          request = jsonDecode(incoming.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'tenant': {
                'id': 'tenant_123',
                'organization_did': 'did:elix:org:ntp',
                'service_slug': 'ntp-party',
                'status': 'draft',
                'approval_threshold': 2,
              },
            }),
            201,
          );
        }),
      );

      final tenant = await client.bootstrap(
        organizationDid: 'did:elix:org:ntp',
        serviceSlug: 'ntp-party',
        approvalThreshold: 2,
        administratorCount: 3,
      );

      expect(tenant.id, 'tenant_123');
      expect(request['owner_custody'], 'hardware');
      expect(request['owner_key_algorithm'], 'p256-sha256');
      expect(request['issued_at'], '2026-07-22T10:00:00Z');
      expect(request['signature_hex'], 'root-signature');
      expect(
        utf8.decode(key.signed.single),
        '{"type":"HostedIssuerBootstrap","version":1,"organization_did":"did:elix:org:ntp","service_slug":"ntp-party","approval_threshold":2,"administrator_count":3,"owner_did":"did:elix:admin:alice","owner_public_key_hex":"${_publicKeyHex()}","owner_key_algorithm":"p256-sha256","owner_custody":"hardware","issued_at":"2026-07-22T10:00:00Z"}',
      );
    },
  );

  test(
    'administrator enrollment signs intent then completes WebAuthn',
    () async {
      final paths = <String>[];
      final key = _FakeRootKey();
      final webAuthn = _FakeWebAuthn();
      final client = HostedIssuerAdminClient(
        baseUrl: 'https://issuer.example',
        ownerDid: 'did:elix:admin:alice',
        rootKey: key,
        webAuthn: webAuthn,
        now: () => DateTime.utc(2026, 7, 22, 10),
        random: Random(7),
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/register/options')) {
            return http.Response(
              jsonEncode({
                'ceremony_id': 'ceremony-1',
                'publicKey': {'challenge': 'challenge'},
              }),
              200,
            );
          }
          expect(
            request.url.queryParameters['admin_did'],
            'did:elix:admin:alice',
          );
          expect(request.url.queryParameters['ceremony_id'], 'ceremony-1');
          return http.Response(jsonEncode({'registered': true}), 200);
        }),
      );

      await client.enrollAdministratorPasskey('tenant_123');

      expect(paths, [
        '/api/v1/hosted-issuers/tenant_123/admin/webauthn/register/options',
        '/api/v1/hosted-issuers/tenant_123/admin/webauthn/register/verify',
      ]);
      expect(webAuthn.registrationOptions, {'challenge': 'challenge'});
      expect(key.signed, hasLength(1));
    },
  );

  test('administrator capability drives KMS delegation lifecycle', () async {
    final requests = <http.Request>[];
    final key = _FakeRootKey();
    final client = HostedIssuerAdminClient(
      baseUrl: 'https://issuer.example',
      ownerDid: 'did:elix:admin:alice',
      rootKey: key,
      webAuthn: _FakeWebAuthn(),
      now: () => DateTime.utc(2026, 7, 22, 10),
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/authenticate/options')) {
          return http.Response(
            jsonEncode({
              'ceremony_id': 'auth-1',
              'publicKey': {'challenge': 'challenge'},
            }),
            200,
          );
        }
        if (path.endsWith('/authenticate/verify')) {
          return http.Response(
            jsonEncode({
              'access_token': 'admin-token',
              'expires_at': '2026-07-22T10:05:00Z',
              'scope':
                  'issuer_admin:audit issuer_admin:delegations issuer_admin:keys',
              'audience': 'https://issuer.example/tenants/tenant_123',
            }),
            200,
          );
        }
        expect(request.headers['authorization'], 'Bearer admin-token');
        if (path.endsWith('/keys')) {
          return http.Response(
            jsonEncode({
              'key': {'id': 'key-1'},
            }),
            201,
          );
        }
        if (path.endsWith('/delegations')) {
          return http.Response(jsonEncode({'id': 'delegation-1'}), 201);
        }
        if (path.endsWith('/audit/export')) {
          return http.Response(jsonEncode({'events': <Object?>[]}), 200);
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    final capability = await client.authenticateAdministrator(
      tenantId: 'tenant_123',
      scopes: const {
        'issuer_admin:keys',
        'issuer_admin:delegations',
        'issuer_admin:audit',
      },
    );
    final applicantKey = _FakeRootKey();
    final applicant = HostedIssuerAdminClient(
      baseUrl: 'https://issuer.example',
      ownerDid: 'did:elix:admin:bob',
      rootKey: applicantKey,
      webAuthn: _FakeWebAuthn(),
      now: () => DateTime.utc(2026, 7, 22, 10),
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    final enrollment = await applicant.createAdministratorEnrollment(
      tenantId: 'tenant_123',
    );
    await client.addAdministrator(
      tenantId: 'tenant_123',
      applicantEnrollment: enrollment,
      capability: capability,
    );
    expect(applicantKey.signed, hasLength(1));
    final registered = await client.registerOperationalKey(
      tenantId: 'tenant_123',
      kmsKeyVersion:
          'projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1',
      version: 1,
      capability: capability,
    );
    expect(registered['id'], 'key-1');

    final payload = HostedIssuerAdminClient.delegationPayload(
      issuerDid: 'did:elix:org:ntp',
      delegateKey: 'did:key:zOperational',
      service: 'https://issuer.example/tenants/tenant_123',
      credentialTypes: const ['PoliticalPartyMembershipCredential'],
      notBefore: DateTime.utc(2026, 7, 22, 10),
      expiresAt: DateTime.utc(2027, 7, 22, 10),
      threshold: 2,
      administratorCount: 3,
      sequence: 1,
    );
    final delegationId = await client.proposeDelegation(
      tenantId: 'tenant_123',
      signingKeyId: 'key-1',
      canonicalPayload: payload,
      capability: capability,
    );
    await client.approveDelegation(
      tenantId: 'tenant_123',
      delegationId: delegationId,
      canonicalPayload: payload,
      capability: capability,
    );
    await client.activateDelegation(
      tenantId: 'tenant_123',
      delegationId: delegationId,
      capability: capability,
    );
    await client.revokeDelegation(
      tenantId: 'tenant_123',
      delegationId: delegationId,
      capability: capability,
    );
    expect(
      await client.exportAudit(tenantId: 'tenant_123', capability: capability),
      isEmpty,
    );
    expect(key.signed, hasLength(2));
    expect(
      requests.where(
        (request) => request.headers['authorization'] == 'Bearer admin-token',
      ),
      hasLength(7),
    );
  });

  test(
    'issuance inbox and status changes are passkey-capability authorized',
    () async {
      final key = _FakeRootKey();
      final requests = <http.Request>[];
      final client = HostedIssuerAdminClient(
        baseUrl: 'https://issuer.example',
        ownerDid: 'did:elix:admin:alice',
        rootKey: key,
        webAuthn: _FakeWebAuthn(),
        now: () => DateTime.utc(2026, 7, 22, 10),
        client: MockClient((request) async {
          requests.add(request);
          expect(request.headers['authorization'], 'Bearer admin-token');
          if (request.method == 'GET') {
            expect(request.url.queryParameters['state'], 'pending');
            return http.Response(
              jsonEncode({
                'requests': [
                  {
                    'id': 'issuance-1',
                    'applicant_hash': 'applicant-hash',
                    'payload_hash': 'payload-hash',
                    'membership_class': 'member',
                    'state': 'pending',
                    'approval_count': 1,
                    'policy_snapshot': {'approval_threshold': 2},
                    'expires_at': '2026-07-29T10:00:00Z',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/decisions')) {
            return http.Response(
              jsonEncode({
                'request': {'state': 'approved'},
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      final capability = HostedIssuerAdminCapability(
        token: 'admin-token',
        expiresAt: DateTime.utc(2026, 7, 22, 10, 5),
        scopes: const {'issuer_admin:issuance', 'issuer_admin:status'},
        audience: 'https://issuer.example/tenants/tenant_123',
      );

      final inbox = await client.listIssuanceRequests(
        tenantId: 'tenant_123',
        capability: capability,
      );
      expect(inbox.single.approvalThreshold, 2);
      expect(
        await client.decideIssuanceRequest(
          tenantId: 'tenant_123',
          requestId: 'issuance-1',
          decision: 'approve',
          capability: capability,
        ),
        'approved',
      );
      await client.setCredentialStatus(
        tenantId: 'tenant_123',
        credentialId: 'credential-1',
        status: 'revoked',
        capability: capability,
      );

      expect(key.signed, hasLength(2));
      expect(
        utf8.decode(key.signed.last),
        contains('"type":"CredentialStatusDecision"'),
      );
      expect(requests, hasLength(3));
    },
  );
}

class _FakeRootKey implements IssuerRootSigningKey {
  final signed = <List<int>>[];

  @override
  Future<IdentityPublicKey> ensureHardwareKey() async => IdentityPublicKey(
    algorithm: IdentityKeyAlgorithm.p256Sha256,
    publicKeyHex: _publicKeyHex(),
    custody: IdentityKeyCustody.hardware,
  );

  @override
  Future<IdentitySignature> sign(List<int> message) async {
    signed.add(List<int>.from(message));
    return const IdentitySignature(
      algorithm: IdentityKeyAlgorithm.p256Sha256,
      hex: 'root-signature',
    );
  }
}

String _publicKeyHex() => '04${List.filled(64, 'ab').join()}';

class _FakeWebAuthn implements WebAuthnPlatform {
  Map<String, dynamic>? registrationOptions;

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> options,
  ) async => {'id': 'assertion-1', 'response': <String, Object?>{}};

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    registrationOptions = options;
    return {'id': 'credential-1', 'response': <String, Object?>{}};
  }
}
