import 'package:drift/drift.dart';

class LocalCollections extends Table {
  TextColumn get collectionId => text()();
  TextColumn get ownerDid => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {collectionId};
}
