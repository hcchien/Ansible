import 'package:drift/drift.dart';

class WalletPresentations extends Table {
  TextColumn get presentationId => text()();
  TextColumn get credentialId => text()();
  TextColumn get verifierAudience => text()();
  TextColumn get nonceHash => text()();
  TextColumn get result => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {presentationId};
}
