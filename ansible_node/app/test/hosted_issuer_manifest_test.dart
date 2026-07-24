import 'dart:convert';

import 'package:ansible_node/services/hosted_issuer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'loads manifest-defined credential configurations and predicates',
    () async {
      final client = HostedIssuerManifestClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'tenant': {'organization_did': 'did:web:party.example'},
              'credential_configurations': [
                {
                  'id': 'party-member-v2',
                  'version': 2,
                  'credential_type': 'OrganizationMembershipCredential',
                  'claims': [
                    {
                      'path': 'membershipActive',
                      'allowed_operators': ['equals'],
                      'disclosable': true,
                      'value_type': 'boolean',
                      'allowed_values': [true],
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final manifest = await client.load(
        Uri.parse('https://issuer.example/manifest'),
      );

      expect(manifest.organizationDid, 'did:web:party.example');
      expect(manifest.configurations.single.id, 'party-member-v2');
      expect(
        manifest.configurations.single.credentialType,
        'OrganizationMembershipCredential',
      );
      expect(
        manifest.configurations.single.claims.single.path,
        'membershipActive',
      );
      expect(
        manifest.configurations.single.claims.single.valueType,
        'boolean',
      );
      expect(
        manifest.configurations.single.claims.single.allowedValues,
        [true],
      );
    },
  );

  test('rejects claims that are not marked disclosable', () async {
    final client = HostedIssuerManifestClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tenant': {'organization_did': 'did:web:party.example'},
            'credential_configurations': [
              {
                'id': 'unsafe',
                'credential_type': 'UnsafeCredential',
                'claims': [
                  {
                    'path': 'nationalId',
                    'allowed_operators': ['equals'],
                    'disclosable': false,
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(
      () => client.load(Uri.parse('https://issuer.example/manifest')),
      throwsA(isA<HostedIssuerManifestException>()),
    );
  });

  test('rejects manifest values that the Relay policy schema would reject', (
  ) async {
    final client = HostedIssuerManifestClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tenant': {'organization_did': 'did:web:party.example'},
            'credential_configurations': [
              {
                'id': 'invalid id with spaces',
                'credential_type': 'OrganizationMembershipCredential',
                'claims': [
                  {
                    'path': 'NationalID',
                    'allowed_operators': ['equals'],
                    'disclosable': true,
                    'value_type': 'string',
                    'allowed_values': ['A123'],
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(
      () => client.load(Uri.parse('https://issuer.example/manifest')),
      throwsA(isA<HostedIssuerManifestException>()),
    );
  });
}
