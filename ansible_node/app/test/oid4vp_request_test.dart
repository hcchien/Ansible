import 'dart:convert';

import 'package:ansible_node/services/oid4vp_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an embedded openid4vp verifier request', () {
    final request = Oid4vpAuthorizationRequest.parse(
      _requestUri(
        clientId: 'https://verifier.example',
        responseUri: 'https://verifier.example/direct_post',
        nonce: 'nonce-123',
        state: 'state-abc',
      ),
    );

    expect(request.clientId, 'https://verifier.example');
    expect(request.audience, 'https://verifier.example');
    expect(
      request.responseUri.toString(),
      'https://verifier.example/direct_post',
    );
    expect(request.nonce, 'nonce-123');
    expect(request.state, 'state-abc');
    expect(request.presentationDefinitionId, 'pd-humanity');
    expect(request.inputDescriptorId, 'humanity-vc');
    expect(request.requiredCredentialType, 'TrisAuraHumanityCredential');
    expect(request.requestedClaimLabels, contains('humanVerified'));
    expect(request.requestedClaimLabels, contains('jurisdiction'));
  });

  test('rejects non-HTTPS response_uri outside local development', () {
    expect(
      () => Oid4vpAuthorizationRequest.parse(
        _requestUri(
          clientId: 'https://verifier.example',
          responseUri: 'http://verifier.example/direct_post',
          nonce: 'nonce-123',
        ),
      ),
      throwsA(
        isA<Oid4vpRequestException>().having(
          (error) => error.code,
          'code',
          'insecure_response_uri',
        ),
      ),
    );
  });

  test('allows localhost response_uri only in local development mode', () {
    final request = Oid4vpAuthorizationRequest.parse(
      _requestUri(
        clientId: 'http://127.0.0.1:8787',
        responseUri: 'http://127.0.0.1:8787/direct_post',
        nonce: 'nonce-123',
      ),
      allowLocalHttp: true,
    );

    expect(request.responseUri.toString(), 'http://127.0.0.1:8787/direct_post');
    expect(request.audience, 'http://127.0.0.1:8787');
  });

  test('rejects malformed credential type requests', () {
    expect(
      () => Oid4vpAuthorizationRequest.parse(
        _requestUri(
          clientId: 'https://verifier.example',
          responseUri: 'https://verifier.example/direct_post',
          nonce: 'nonce-123',
          credentialType: 'EmailToken',
        ),
      ),
      throwsA(
        isA<Oid4vpRequestException>().having(
          (error) => error.code,
          'code',
          'unsupported_credential_type',
        ),
      ),
    );
  });

  test('accepts a manifest-defined credential type without an app release', () {
    final request = Oid4vpAuthorizationRequest.parse(
      _requestUri(
        clientId: 'https://verifier.example',
        responseUri: 'https://verifier.example/direct_post',
        nonce: 'nonce-123',
        credentialType: 'OrganizationMembershipCredential',
      ),
    );

    expect(request.requiredCredentialType, 'OrganizationMembershipCredential');
  });

  test('rejects request_uri-only verifier requests for the MVP', () {
    expect(
      () => Oid4vpAuthorizationRequest.parse(
        'openid4vp://authorize?client_id=https%3A%2F%2Fverifier.example'
        '&request_uri=https%3A%2F%2Fverifier.example%2Frequest.jwt',
      ),
      throwsA(
        isA<Oid4vpRequestException>().having(
          (error) => error.code,
          'code',
          'request_uri_not_supported',
        ),
      ),
    );
  });
}

String _requestUri({
  required String clientId,
  required String responseUri,
  required String nonce,
  String credentialType = 'TrisAuraHumanityCredential',
  String? state,
}) {
  final definition = {
    'id': 'pd-humanity',
    'input_descriptors': [
      {
        'id': 'humanity-vc',
        'name': 'Verified human credential',
        'constraints': {
          'fields': [
            {
              'path': [r'$.type'],
              'filter': {
                'type': 'array',
                'contains': {'const': credentialType},
              },
            },
            {
              'path': [r'$.credentialSubject.humanVerified'],
            },
            {
              'path': [r'$.credentialSubject.jurisdiction'],
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
      'client_id': clientId,
      'response_type': 'vp_token',
      'response_mode': 'direct_post',
      'response_uri': responseUri,
      'nonce': nonce,
      if (state != null) 'state': state,
      'presentation_definition': jsonEncode(definition),
    },
  ).toString();
}
