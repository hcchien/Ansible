import 'package:drift/drift.dart';

class MessengerSessions extends Table {
  TextColumn get localDeviceId => text()();
  TextColumn get remoteDeviceId => text()();
  TextColumn get remoteDid => text()();
  TextColumn get protocolVersion =>
      text().withDefault(const Constant('signal-mvp-v1'))();
  TextColumn get sessionState => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localDeviceId, remoteDeviceId};
}
