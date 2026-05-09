import 'package:drift/drift.dart';

class PublicationIntents extends Table {
  TextColumn get intentId => text()();
  TextColumn get authorDid => text()();
  TextColumn get contentItemId => text()();
  TextColumn get action => text()();
  TextColumn get visibility => text()();
  TextColumn get distributionPreference => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get payloadHash => text().nullable()();
  TextColumn get signature => text().nullable()();
  TextColumn get signatureScheme => text().nullable()();
  DateTimeColumn get signedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get error => text().nullable()();

  @override
  Set<Column> get primaryKey => {intentId};
}
