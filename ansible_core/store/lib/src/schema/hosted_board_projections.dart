import 'package:drift/drift.dart';

class HostedBoardProjections extends Table {
  TextColumn get localBoardId => text()();
  TextColumn get forumHostId => text()();
  TextColumn get hostedBoardId => text()();
  TextColumn get canonicalBoardUri => text()();
  TextColumn get remoteSlug => text()();
  TextColumn get localSlug => text().unique()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get permissionsJson => text().withDefault(const Constant('{}'))();
  IntColumn get lastSeenCursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {localBoardId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {forumHostId, hostedBoardId},
  ];
}
