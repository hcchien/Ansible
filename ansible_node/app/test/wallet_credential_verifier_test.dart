import 'dart:convert';
import 'dart:io';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:ansible_node/services/wallet_credential_verifier.dart';
import 'package:ansible_node/services/oid4vp_presentation_service.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/services/identity_anchor_service.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/elix_go_issuer_vc.json').readAsStringSync())
        as Map<String, dynamic>;
void main() {
  test(
    'verifies real Go Issuer signature, rejects altered payload and unauthorized key',
    () async {
      final data = fixture();
      var doc = data['did_document'] as Map;
      final verifier = WalletCredentialVerifier(
        trustedIssuers: {'did:web:issuer.elix.cool'},
        client: MockClient((r) async => http.Response(jsonEncode(doc), 200)),
      );
      final raw = (data['credential'] as Map).cast<String, Object?>();
      expect(await verifier.verify(TrisAuraCredential.fromJson(raw)), true);
      final tampered = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      tampered['credentialSubject']['humanVerified'] = false;
      expect(
        await verifier.verify(TrisAuraCredential.fromJson(tampered)),
        false,
      );
      doc = {...doc, 'assertionMethod': <Object>[]};
      expect(await verifier.verify(TrisAuraCredential.fromJson(raw)), false);
    },
  );

  test(
    'status is fail closed for revoked, unknown, errors, redirects and foreign origins',
    () async {
      final data = fixture();
      final credential = TrisAuraCredential.fromJson(
        (data['credential'] as Map).cast<String, Object?>(),
      );
      final statusId = Uri.parse(
        credential.credentialStatus.single['id'] as String,
      ).pathSegments.last;
      var code = 200;
      Object response = {'id': statusId, 'status': 'active', 'revoked': false};
      var requests = 0;
      final verifier = WalletCredentialVerifier(
        trustedIssuers: {'did:web:issuer.elix.cool'},
        client: MockClient((r) async {
          requests++;
          return http.Response(
            jsonEncode(response),
            code,
            headers: {'location': 'https://evil.example'},
          );
        }),
      );
      expect(await verifier.status(credential), CredentialStatus.active);
      response = {'id': statusId, 'status': 'revoked', 'revoked': true};
      expect(await verifier.status(credential), CredentialStatus.revoked);
      response = {'id': statusId, 'status': 'unknown'};
      expect(await verifier.status(credential), CredentialStatus.unknown);
      code = 503;
      expect(await verifier.status(credential), CredentialStatus.unknown);
      code = 302;
      expect(await verifier.status(credential), CredentialStatus.unknown);
      final raw =
          jsonDecode(jsonEncode(data['credential'])) as Map<String, dynamic>;
      raw['credentialStatus'] = {
        'id': 'https://evil.example/api/v1/vc/status/abc',
        'type': 'TrisAuraStatusEndpoint2024',
      };
      final before = requests;
      expect(
        await verifier.status(TrisAuraCredential.fromJson(raw)),
        CredentialStatus.unknown,
      );
      expect(requests, before);
    },
  );

  test(
    'active P256 holder matches independently verified OpenSSL Data Integrity fixture',
    () async {
      final data =
          jsonDecode(
                File(
                  'test/fixtures/elix_openssl_p256_vp.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final key = _P256Key(data);
      final identity = CanonicalIdentity(
        did: 'did:elix:hardware',
        handle: 'test.elix.cool',
        publicKeyHex: await key.publicKeyHex(),
        signingAlgorithm: 'p256-sha256',
        custody: 'hardware',
      );
      final signer = LocalVpProofSigner(
        identityKey: key,
        identityStore: InMemoryCanonicalIdentityStore(identity),
      );
      final options = await signer.proofOptions(identity.did);
      expect(options['cryptosuite'], 'ecdsa-jcs-2019');
      expect(options['verificationMethod'], '${identity.did}#identity');
      final unsigned = (data['presentation'] as Map).cast<String, Object?>();
      final proof = await signer.signPresentation(
        unsignedPresentation: unsigned,
        canonicalPayload: credentialCanonicalJson(unsigned),
      );
      expect(proof, data['proof_value']);
      await expectLater(
        signer.proofOptions('did:elix:other'),
        throwsA(isA<Oid4vpSubmissionException>()),
      );
    },
  );
}

class _P256Key extends IdentityKey {
  _P256Key(this.data);
  final Map<String, dynamic> data;
  @override
  Future<String> algorithm() async => 'p256-sha256';
  @override
  Future<String> publicKeyHex() async => data['public_key_hex'] as String;
  @override
  Future<String> sign(List<int> message) async {
    expect(
      message.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      data['hash_data_hex'],
    );
    return data['signature_der_hex'] as String;
  }
}
