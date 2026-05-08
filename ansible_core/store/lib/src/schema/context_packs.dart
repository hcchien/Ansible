import 'package:drift/drift.dart';

class ContextPacks extends Table {
  TextColumn get contextPackId => text()();
  TextColumn get purpose => text()();
  TextColumn get sourceRefsJson => text()();
  TextColumn get snapshotJson => text()();
  TextColumn get privacyLevel => text()();
  BoolColumn get allowedRemote =>
      boolean().withDefault(const Constant(false))();
  TextColumn get createdByDid => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {contextPackId};
}
