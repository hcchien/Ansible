import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds ICAO BAC/PACE MRZ access key with check digits', () {
    const access = PassportAccessData(
      documentNumber: '12345678',
      dateOfBirth: '980127',
      dateOfExpiry: '250830',
    );

    expect(access.normalizedDocumentNumber, '12345678<');
    expect(access.mrzKey, '12345678<898012772508304');
  });

  test('rejects malformed dates before opening an NFC session', () {
    const access = PassportAccessData(
      documentNumber: '123456789',
      dateOfBirth: '1998-01-27',
      dateOfExpiry: '250830',
    );

    expect(access.validate, throwsFormatException);
  });
}
