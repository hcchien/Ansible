import 'package:drift/drift.dart';

class RemoteNodes extends Table {
  TextColumn get nodeId => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get accessToken => text().nullable()();
  IntColumn get syncCursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {nodeId};
}
