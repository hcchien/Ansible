import 'package:drift/drift.dart';

import 'follow_edges.dart';

class FollowActivityEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get followId => text().references(FollowEdges, #followId)();
  TextColumn get eventType => text()();
  TextColumn get actorDid => text()();
  TextColumn get activityId => text().nullable()();
  TextColumn get message => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {eventId};
}
