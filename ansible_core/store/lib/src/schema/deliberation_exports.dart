import 'package:drift/drift.dart';

/// A user-created, expiring snapshot made explicitly available to Local AI.
///
/// This is not a sync projection. No row is written merely by opening or
/// participating in a deliberation; the client writes one only after the user
/// invokes the export action and the Forum Host authorizes the requested view.
@DataClassName('DeliberationExportRow')
class DeliberationExports extends Table {
  TextColumn get exportId => text()();
  TextColumn get boardId => text()();
  TextColumn get deliberationId => text()();
  TextColumn get title => text()();
  TextColumn get view => text()();
  TextColumn get manifestJson => text()();
  TextColumn get reportJson => text()();
  TextColumn get statementsJson => text().nullable()();
  TextColumn get responsesJson => text().nullable()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {exportId};
}
