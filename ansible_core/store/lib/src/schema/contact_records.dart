import 'package:drift/drift.dart';

class ContactRecords extends Table {
  TextColumn get subjectDid => text()();
  TextColumn get handle => text().nullable().unique()();
  TextColumn get displayName => text().nullable()();
  TextColumn get localAlias => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get relationship =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get source => text().withDefault(const Constant('unknown'))();
  TextColumn get trustState =>
      text().withDefault(const Constant('unverified'))();
  TextColumn get messengerAvailability =>
      text().withDefault(const Constant('unresolved'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastResolvedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {subjectDid};
}
