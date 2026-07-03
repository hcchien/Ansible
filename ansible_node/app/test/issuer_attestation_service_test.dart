import 'dart:convert';

import 'package:ansible_store/ansible_store.dart' show encodeDidKeyEd25519;
import 'package:ansible_vc/ansible_vc.dart' show VpBuilder;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/issuer_attestation_service.dart';

void main() {
  const holderDid = 'did:elix:abcdefghijklmnop';
  const issuerHost = 'issuer.test';
  const issuerDid = 'did:web:$issuerHost';

  final issuerKey = InMemoryIdentityKey(
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );

  Map<String, Object?> vcWithoutProof({
    String subject = holderDid,
    String issuer = issuerDid,
    String credentialType = 'TrisAuraHumanityCredential',
    String? validUntil,
  }) {
    return {
      '@context': [
        'https://www.w3.org/ns/credentials/v2',
        'https://elix.cool/contexts/humanity/v1',
      ],
      'id': 'https://$issuerHost/vc/test001',
      'type': ['VerifiableCredential', credentialType],
      'issuer': issuer,
      'validFrom': '2026-01-01T00:00:00Z',
      'validUntil': validUntil ?? '2027-01-01T00:00:00Z',
      'credentialSubject': {
        'id': subject,
        'humanVerified': true,
        'jurisdiction': 'TW',
      },
    };
  }

  Future<Map<String, Object?>> signedVc(Map<String, Object?> body) async {
    // Sign the SAME canonical form the relay verifies and serves — deep-sorted
    // compact JSON (VpBuilder.canonicalPayload == deep_sort_keys|>Jason.encode!).
    final proofValue = await issuerKey.sign(
      utf8.encode(VpBuilder.canonicalPayload(body)),
    );
    return {
      ...body,
      'proof': {
        'type': 'Ed25519Signature2020',
        'created': '2026-01-01T00:00:00Z',
        'verificationMethod': '$issuerDid#key-1',
        'proofPurpose': 'assertionMethod',
        'proofValue': proofValue,
      },
    };
  }

  Future<MockClient> relayServing(Map<String, Object?>? vc) async {
    final issuerPubHex = await issuerKey.publicKeyHex();
    final multibase =
        encodeDidKeyEd25519(issuerPubHex).replaceFirst('did:key:', '');
    return MockClient((request) async {
      if (request.url.path == '/.well-known/did.json') {
        return http.Response(
          jsonEncode({
            'id': issuerDid,
            'verificationMethod': [
              {
                'id': '$issuerDid#key-1',
                'type': 'Multikey',
                'controller': issuerDid,
                'publicKeyMultibase': multibase,
              }
            ],
          }),
          200,
        );
      }
      if (request.url.path.contains('/identity/attestation/')) {
        if (vc == null) {
          return http.Response('{"error":"attestation_not_found"}', 404);
        }
        return http.Response(
          jsonEncode({
            'did': holderDid,
            'credential_type': 'TrisAuraHumanityCredential',
            // Deliberately wrong: the service must derive the tier from the
            // verified credential type, never trust this field.
            'reputation_tier': 'server_says_admin',
            'vc': vc,
            'presented_at': '2026-07-01T00:00:00Z',
          }),
          200,
        );
      }
      return http.Response('{"error":"unexpected"}', 500);
    });
  }

  IssuerAttestationService serviceWith(MockClient client) {
    return IssuerAttestationService(
      relayBaseUrl: 'http://relay.test',
      issuerBaseUrl: 'https://$issuerHost',
      client: client,
      now: () => DateTime.utc(2026, 7, 3),
    );
  }

  test('multibase decoder inverts the did:key encoder', () async {
    final pubHex = await issuerKey.publicKeyHex();
    final multibase = encodeDidKeyEd25519(pubHex).replaceFirst('did:key:', '');
    expect(decodeEd25519Multibase(multibase), pubHex);
    expect(decodeEd25519Multibase('not-multibase'), isNull);
    expect(decodeEd25519Multibase('z'), isNull);
  });

  test('a valid issuer-signed humanity VC yields verified_human', () async {
    final vc = await signedVc(vcWithoutProof());
    final service = serviceWith(await relayServing(vc));
    expect(await service.verifiedTierFor(holderDid), 'verified_human');
  });

  test('EmailCredential maps to basic, not verified_human', () async {
    final vc = await signedVc(vcWithoutProof(credentialType: 'EmailCredential'));
    final service = serviceWith(await relayServing(vc));
    expect(await service.verifiedTierFor(holderDid), 'basic');
  });

  test('a tampered VC body fails the issuer proof (fail closed)', () async {
    final vc = await signedVc(vcWithoutProof());
    final subject =
        (vc['credentialSubject']! as Map).cast<String, Object?>();
    final tampered = {
      ...vc,
      'credentialSubject': {...subject, 'humanVerified': false},
    };
    final service = serviceWith(await relayServing(tampered));
    expect(await service.verifiedTierFor(holderDid), isNull);
  });

  test('a VC for a different subject is rejected', () async {
    final vc = await signedVc(vcWithoutProof(subject: 'did:elix:someoneelse'));
    final service = serviceWith(await relayServing(vc));
    expect(await service.verifiedTierFor(holderDid), isNull);
  });

  test('a VC from a non-pinned issuer is rejected', () async {
    final vc = await signedVc(vcWithoutProof(issuer: 'did:web:evil.example'));
    final service = serviceWith(await relayServing(vc));
    expect(await service.verifiedTierFor(holderDid), isNull);
  });

  test('an expired VC is rejected', () async {
    final vc =
        await signedVc(vcWithoutProof(validUntil: '2026-06-01T00:00:00Z'));
    final service = serviceWith(await relayServing(vc));
    expect(await service.verifiedTierFor(holderDid), isNull);
  });

  test('no attestation (404) yields null and is cached', () async {
    var calls = 0;
    final issuerPubHex = await issuerKey.publicKeyHex();
    final multibase =
        encodeDidKeyEd25519(issuerPubHex).replaceFirst('did:key:', '');
    final client = MockClient((request) async {
      if (request.url.path == '/.well-known/did.json') {
        return http.Response(
          jsonEncode({
            'verificationMethod': [
              {'publicKeyMultibase': multibase},
            ],
          }),
          200,
        );
      }
      calls += 1;
      return http.Response('{"error":"attestation_not_found"}', 404);
    });
    final service = serviceWith(client);
    expect(await service.verifiedTierFor(holderDid), isNull);
    expect(await service.verifiedTierFor(holderDid), isNull);
    expect(calls, 1, reason: 'definitive negatives are cached');
  });
}
