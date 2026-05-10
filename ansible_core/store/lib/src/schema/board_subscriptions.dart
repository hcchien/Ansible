import 'package:drift/drift.dart';

class BoardSubscriptions extends Table {
  TextColumn get subscriptionId => text()();
  TextColumn get forumHostId => text()();
  TextColumn get hostedBoardId => text()();
  TextColumn get localBoardId => text()();
  BoolColumn get readEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get writeEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get syncCursor => integer().withDefault(const Constant(0))();
  IntColumn get retentionDays => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {subscriptionId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {forumHostId, hostedBoardId},
  ];
}
