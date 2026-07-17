import 'package:drift/drift.dart';

@DataClassName('RemoteTombstoneRow')
class RemoteTombstones extends Table {
  TextColumn get sourceNodeId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get boardId => text().nullable()();
  TextColumn get authorDid => text().nullable()();
  TextColumn get deletedByDid => text()();
  DateTimeColumn get deletedAt => dateTime()();
  DateTimeColumn get receivedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sourceNodeId, entityType, entityId};
}
