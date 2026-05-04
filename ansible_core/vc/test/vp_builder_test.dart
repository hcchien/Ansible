import 'package:ansible_vc/ansible_vc.dart';
import 'package:test/test.dart';

import 'fixtures/humanity_credential_fixtures.dart';

void main() {
  group('VpBuilder', () {
    test('builds presentation bound to nonce and audience', () {
      final credential = TrisAuraCredential.fromJson(humanityFixture);

      final vp = VpBuilder.build(
        credential: credential,
        holderDid: 'did:key:z6Mkholder',
        nonce: 'nonce-123',
        audience: 'https://relay.trisaura.io',
        proofValue: 'test-signature',
        createdAt: DateTime.utc(2026, 5, 4, 10),
      );

      expect(vp['holder'], 'did:key:z6Mkholder');
      expect(vp['verifiableCredential'], [humanityFixture]);
      expect((vp['proof']! as Map<String, Object?>)['challenge'], 'nonce-123');
      expect(
        (vp['proof']! as Map<String, Object?>)['domain'],
        'https://relay.trisaura.io',
      );
    });

    test('refuses to build presentation for a different holder', () {
      final credential = TrisAuraCredential.fromJson(humanityFixture);

      expect(
        () => VpBuilder.build(
          credential: credential,
          holderDid: 'did:key:z6Mkother',
          nonce: 'nonce-123',
          audience: 'https://relay.trisaura.io',
          proofValue: 'test-signature',
        ),
        throwsA(
          isA<TrisAuraCredentialException>().having(
            (error) => error.code,
            'code',
            'holder_mismatch',
          ),
        ),
      );
    });
  });
}
