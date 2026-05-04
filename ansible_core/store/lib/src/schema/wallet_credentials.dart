import 'package:drift/drift.dart';

class WalletCredentials extends Table {
  TextColumn get credentialId => text()();
  TextColumn get issuerDid => text()();
  TextColumn get holderDid => text()();
  TextColumn get credentialType => text()();
  TextColumn get status => text()();
  DateTimeColumn get validFrom => dateTime()();
  DateTimeColumn get validUntil => dateTime()();
  TextColumn get displayName => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {credentialId};
}
