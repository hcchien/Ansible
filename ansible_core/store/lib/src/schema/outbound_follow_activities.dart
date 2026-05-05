import 'package:drift/drift.dart';

class OutboundFollowActivities extends Table {
  TextColumn get outboxId => text()();
  TextColumn get activityId => text().unique()();
  TextColumn get activityType => text()();
  TextColumn get targetInboxUri => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deliveredAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {outboxId};
}
