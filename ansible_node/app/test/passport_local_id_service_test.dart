import 'package:ansible_node/services/passport_local_id_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PassportLocalIdService', () {
    test('derives the same local id for the same passport and secret', () {
      final service = PassportLocalIdService.fixedSecret('wallet-secret');

      final first = service.derive(
        nationality: 'twn',
        documentNumber: '300012345',
      );
      final second = service.derive(
        nationality: 'TWN',
        documentNumber: '300012345',
      );

      expect(first, second);
      expect(first, startsWith('passport-local-v1-'));
    });

    test('derives different local ids for different passports', () {
      final service = PassportLocalIdService.fixedSecret('wallet-secret');

      final first = service.derive(
        nationality: 'TWN',
        documentNumber: '300012345',
      );
      final second = service.derive(
        nationality: 'TWN',
        documentNumber: '300012346',
      );

      expect(first, isNot(second));
    });

    test('derives different local ids for different wallet secrets', () {
      final first = PassportLocalIdService.fixedSecret('wallet-secret-a')
          .derive(nationality: 'TWN', documentNumber: '300012345');
      final second = PassportLocalIdService.fixedSecret('wallet-secret-b')
          .derive(nationality: 'TWN', documentNumber: '300012345');

      expect(first, isNot(second));
    });

    test('does not expose the raw passport number in the derived id', () {
      final id = PassportLocalIdService.fixedSecret('wallet-secret').derive(
        nationality: 'TWN',
        documentNumber: '300012345',
      );

      expect(id, isNot(contains('300012345')));
    });
  });
}
