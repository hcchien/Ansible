import 'package:drift/drift.dart';

import 'content_items.dart';

class TransformationJobs extends Table {
  TextColumn get transformationJobId => text()();
  TextColumn get requestedByDid => text()();
  TextColumn get targetMode => text()();
  TextColumn get providerType => text()();
  TextColumn get promptProfile => text().nullable()();
  TextColumn get status => text()();
  TextColumn get inputSnapshotJson => text().nullable()();
  TextColumn get outputSnapshotJson => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {transformationJobId};
}

class TransformationSources extends Table {
  TextColumn get transformationJobId =>
      text().references(TransformationJobs, #transformationJobId)();
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  IntColumn get sourceOrder => integer()();

  @override
  Set<Column> get primaryKey => {transformationJobId, contentItemId};
}
