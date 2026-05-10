import 'package:drift/drift.dart';

class ForumHosts extends Table {
  TextColumn get forumHostId => text()();
  TextColumn get displayName => text()();
  TextColumn get baseUrl => text()();
  TextColumn get canonicalHostUri => text()();
  TextColumn get serverKind => text()();
  TextColumn get capabilitiesJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {forumHostId};
}
