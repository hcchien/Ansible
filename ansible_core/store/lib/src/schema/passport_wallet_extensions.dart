import 'package:drift/drift.dart';

@DataClassName('PassportWalletExtensionRecord')
class PassportWalletExtensions extends Table {
  TextColumn get credentialId => text()();
  TextColumn get passportLocalUniqueId => text().unique()();
  TextColumn get nationalIdHash => text().withDefault(const Constant(''))();
  TextColumn get passportNumberHash => text().withDefault(const Constant(''))();
  TextColumn get nationality => text()();
  TextColumn get assuranceMethod => text()();
  DateTimeColumn get verifiedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {credentialId};
}
