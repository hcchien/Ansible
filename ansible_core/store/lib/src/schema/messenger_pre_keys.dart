import 'package:drift/drift.dart';

class MessengerPreKeys extends Table {
  TextColumn get deviceId => text()();
  IntColumn get preKeyId => integer()();
  TextColumn get publicKey => text()();
  TextColumn get privateKeyRef => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  DateTimeColumn get consumedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {deviceId, preKeyId};
}
