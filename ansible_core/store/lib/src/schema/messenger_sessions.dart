import 'package:drift/drift.dart';

class MessengerSessions extends Table {
  TextColumn get localDeviceId => text()();
  TextColumn get remoteDeviceId => text()();
  TextColumn get remoteDid => text()();
  TextColumn get sessionState => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localDeviceId, remoteDeviceId};
}
