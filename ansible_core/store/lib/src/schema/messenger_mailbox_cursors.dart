import 'package:drift/drift.dart';

class MessengerMailboxCursors extends Table {
  TextColumn get localDeviceId => text()();
  TextColumn get cursor => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localDeviceId};
}
