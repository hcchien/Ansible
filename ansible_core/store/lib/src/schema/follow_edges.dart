import 'package:drift/drift.dart';

import 'follow_targets.dart';

class FollowEdges extends Table {
  TextColumn get followId => text()();
  TextColumn get followerDid => text()();
  TextColumn get targetId => text().references(FollowTargets, #targetId)();
  TextColumn get targetType => text()();
  TextColumn get direction => text()();
  TextColumn get status => text()();
  TextColumn get visibility => text()();
  TextColumn get remoteActivityId => text().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get acceptedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {followId};
}
