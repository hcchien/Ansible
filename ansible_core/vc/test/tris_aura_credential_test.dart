import 'package:ansible_vc/ansible_vc.dart';
import 'package:test/test.dart';

import 'fixtures/humanity_credential_fixtures.dart';

void main() {
  group('TrisAuraCredential', () {
    test('parses a humanity credential without exposing prohibited claims', () {
      final credential = TrisAuraCredential.fromJson(humanityFixture);

      expect(credential.id, 'urn:uuid:test-humanity');
      expect(credential.issuerDid, 'did:web:issuer.elix.cool');
      expect(credential.holderDid, 'did:key:z6Mkholder');
      expect(credential.types, contains('TrisAuraHumanityCredential'));
      expect(credential.claims['humanVerified'], true);
      expect(credential.claims.containsKey('nationalId'), isFalse);
      expect(credential.claims.containsKey('legalName'), isFalse);
    });

    test('rejects credentials with prohibited claims', () {
      final json = Map<String, Object?>.from(humanityFixture);
      json['credentialSubject'] = {
        ...humanityFixture['credentialSubject']! as Map<String, Object?>,
        'nationalId': 'A123456789',
      };

      expect(
        () => TrisAuraCredential.fromJson(json),
        throwsA(
          isA<TrisAuraCredentialException>().having(
            (error) => error.code,
            'code',
            'prohibited_claim',
          ),
        ),
      );
    });

    test('rejects nested prohibited claims', () {
      final json = Map<String, Object?>.from(humanityFixture);
      json['credentialSubject'] = {
        ...humanityFixture['credentialSubject']! as Map<String, Object?>,
        'profile': {
          'evidence': {'rawProviderAssertion': 'signed-provider-token'},
        },
      };

      expect(
        () => TrisAuraCredential.fromJson(json),
        throwsA(
          isA<TrisAuraCredentialException>().having(
            (error) => error.code,
            'code',
            'prohibited_claim',
          ),
        ),
      );
    });

    test('rejects passport identifiers and personhood hashes', () {
      for (final prohibited in [
        'documentNumber',
        'passportNumber',
        'passportLocalUniqueId',
        'nationalIdHash',
        'national_id_hash',
        'passportNumberHash',
        'passport_number_hash',
      ]) {
        final json = Map<String, Object?>.from(humanityFixture);
        json['credentialSubject'] = {
          ...humanityFixture['credentialSubject']! as Map<String, Object?>,
          prohibited: 'opaque-or-raw-value',
        };

        expect(
          () => TrisAuraCredential.fromJson(json),
          throwsA(
            isA<TrisAuraCredentialException>().having(
              (error) => error.code,
              'code',
              'prohibited_claim',
            ),
          ),
          reason: 'credentialSubject must reject $prohibited',
        );
      }
    });

    test('expired credential fails verification result', () {
      final credential = TrisAuraCredential.fromJson(expiredHumanityFixture);
      final verifier = VcVerifier(
        proofVerifier: FakeProofVerifier.valid(),
        trustedIssuers: {'did:web:issuer.elix.cool'},
        statusResolver: (_) async => CredentialStatus.active,
      );

      final result = verifier.verifyCredential(
        credential,
        now: DateTime.utc(2026, 9, 1),
      );

      expect(result.isValid, isFalse);
      expect(result.error, 'credential_expired');
    });

    test('untrusted issuer fails verification result', () {
      final credential = TrisAuraCredential.fromJson(humanityFixture);
      final verifier = VcVerifier(
        proofVerifier: FakeProofVerifier.valid(),
        trustedIssuers: {'did:web:other.example'},
        statusResolver: (_) async => CredentialStatus.active,
      );

      final result = verifier.verifyCredential(
        credential,
        now: DateTime.utc(2026, 5, 5),
      );

      expect(result.isValid, isFalse);
      expect(result.error, 'untrusted_issuer');
    });

    test('revoked credential fails async status verification', () async {
      final credential = TrisAuraCredential.fromJson(humanityFixture);
      final verifier = VcVerifier(
        proofVerifier: FakeProofVerifier.valid(),
        trustedIssuers: {'did:web:issuer.elix.cool'},
        statusResolver: (_) async => CredentialStatus.revoked,
      );

      final result = await verifier.verifyCredentialStatus(
        credential,
        now: DateTime.utc(2026, 5, 5),
      );

      expect(result.isValid, isFalse);
      expect(result.error, 'credential_revoked');
    });

    test('invalid proof fails verification result', () {
      final credential = TrisAuraCredential.fromJson(humanityFixture);
      final verifier = VcVerifier(
        proofVerifier: FakeProofVerifier.invalid(),
        trustedIssuers: {'did:web:issuer.elix.cool'},
        statusResolver: (_) async => CredentialStatus.active,
      );

      final result = verifier.verifyCredential(
        credential,
        now: DateTime.utc(2026, 5, 5),
      );

      expect(result.isValid, isFalse);
      expect(result.error, 'invalid_proof');
    });
  });
}
