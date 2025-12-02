import 'package:drift/drift.dart';

class ActivityLog extends Table {
  IntColumn get logId => integer().autoIncrement()();
  TextColumn get activityId => text().unique()();
  TextColumn get originNodeId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get boardId => text().nullable()();
  TextColumn get threadId => text().nullable()();
  TextColumn get authorId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get payload => text()(); // JSON string
  DateTimeColumn get insertedAt => dateTime().withDefault(currentDateAndTime)();
}
