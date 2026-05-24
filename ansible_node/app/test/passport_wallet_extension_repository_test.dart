import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WalletRepository passport extension storage', () {
    test('saves and finds a passport extension by local unique id', () async {
      final repo = InMemoryWalletRepository();
      final extension = PassportWalletExtension(
        credentialId: 'urn:uuid:passport',
        passportLocalUniqueId: 'passport-local-v1-abc',
        nationalIdHash: 'national-id-hash-abc',
        passportNumberHash: 'passport-number-hash-abc',
        nationality: 'TWN',
        assuranceMethod: 'passport_nfc',
        verifiedAt: DateTime.utc(2026, 5, 24),
      );

      await repo.savePassportExtension(extension);

      final found = await repo.getPassportExtensionByLocalUniqueId(
        'passport-local-v1-abc',
      );
      expect(found?.credentialId, 'urn:uuid:passport');
      expect(found?.nationalIdHash, 'national-id-hash-abc');
      expect(found?.passportNumberHash, 'passport-number-hash-abc');
      expect(found?.nationality, 'TWN');
      expect(found?.assuranceMethod, 'passport_nfc');
    });

    test('passport extension does not expose a raw document number', () {
      final extension = PassportWalletExtension(
        credentialId: 'urn:uuid:passport',
        passportLocalUniqueId: 'passport-local-v1-abc',
        nationalIdHash: 'national-id-hash-abc',
        passportNumberHash: 'passport-number-hash-abc',
        nationality: 'TWN',
        assuranceMethod: 'passport_nfc',
        verifiedAt: DateTime.utc(2026, 5, 24),
      );

      final json = extension.toJson();

      expect(json.keys, isNot(contains('documentNumber')));
      expect(json.keys, isNot(contains('passportNumber')));
    });
  });
}
