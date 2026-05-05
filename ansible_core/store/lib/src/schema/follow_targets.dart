import 'package:drift/drift.dart';

class FollowTargets extends Table {
  TextColumn get targetId => text()();
  TextColumn get targetType => text()();
  TextColumn get canonicalUri => text().nullable().unique()();
  TextColumn get displayName => text()();
  TextColumn get handle => text().nullable()();
  TextColumn get did => text().nullable()();
  TextColumn get actorUri => text().nullable()();
  TextColumn get inboxUri => text().nullable()();
  TextColumn get outboxUri => text().nullable()();
  TextColumn get remoteNodeId => text().nullable()();
  TextColumn get boardId => text().nullable()();
  TextColumn get boardSlug => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {targetId};
}
