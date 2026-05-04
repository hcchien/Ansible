import 'package:drift/drift.dart';

class WalletCredentialPayloads extends Table {
  TextColumn get credentialId => text()();
  TextColumn get encryptedPayload => text()();
  TextColumn get encryptionVersion => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {credentialId};
}
