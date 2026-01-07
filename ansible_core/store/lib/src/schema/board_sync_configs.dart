import 'package:drift/drift.dart';

class BoardSyncConfigs extends Table {
  TextColumn get configId => text()();
  TextColumn get remoteNodeId => text()();
  TextColumn get boardId => text()();
  BoolColumn get syncEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {configId};
}
