import 'package:drift/drift.dart';

class IdentityBindings extends Table {
  TextColumn get bindingId => text()();
  TextColumn get localAccountDid => text()();
  TextColumn get bindingType => text()();
  TextColumn get identifier => text()();
  TextColumn get publicKey => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bindingId};
}
