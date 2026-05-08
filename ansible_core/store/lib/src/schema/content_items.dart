import 'package:drift/drift.dart';

class ContentItems extends Table {
  TextColumn get contentItemId => text()();
  TextColumn get authorDid => text()();
  TextColumn get subjectId => text().nullable()();
  TextColumn get mode => text()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text()();
  TextColumn get status => text()();
  TextColumn get visibility => text()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get localOnly => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {contentItemId};
}
