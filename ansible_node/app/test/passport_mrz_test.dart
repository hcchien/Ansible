import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TD3 MRZ produces BAC/PACE access data after check-digit validation',
    () {
      final access = PassportAccessData.fromTd3Mrz(
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
      );
      expect(access.documentNumber, 'L898902C3');
      expect(access.dateOfBirth, '740812');
      expect(access.dateOfExpiry, '120415');
      expect(access.mrzKey, 'L898902C3674081221204159');
    },
  );

  test('TD3 MRZ rejects an OCR mutation instead of guessing identity data', () {
    expect(
      () => PassportAccessData.fromTd3Mrz(
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        'L898902C36UTO7408122F1204169ZE184226B<<<<<10',
      ),
      throwsFormatException,
    );
  });
}
