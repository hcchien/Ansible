import 'package:drift/drift.dart';

class BoardPublicationTargets extends Table {
  TextColumn get targetId => text()();
  TextColumn get localSourceId => text()();
  TextColumn get sourceType => text()();
  TextColumn get forumHostId => text()();
  TextColumn get hostedBoardId => text()();
  TextColumn get mode => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get remoteThreadId => text().nullable()();
  TextColumn get remotePostId => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {targetId};
}
