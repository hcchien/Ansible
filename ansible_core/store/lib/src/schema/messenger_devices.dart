import 'package:drift/drift.dart';

class MessengerDevices extends Table {
  TextColumn get deviceId => text()();
  TextColumn get subjectDid => text()();
  TextColumn get identityKeyPublic => text()();
  TextColumn get identityKeyPrivateRef => text().nullable()();
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();
  IntColumn get signedPreKeyId => integer().nullable()();
  TextColumn get signedPreKeyPublic => text().nullable()();
  TextColumn get signedPreKeyPrivateRef => text().nullable()();
  TextColumn get signedPreKeySignature => text().nullable()();
  TextColumn get bindingJson => text().nullable()();
  TextColumn get bindingSignature => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {deviceId};
}
