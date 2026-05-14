import 'package:drift/drift.dart';

class MessengerMessages extends Table {
  TextColumn get messageId => text()();
  TextColumn get conversationId => text()();
  TextColumn get direction => text()();
  TextColumn get status => text()();
  TextColumn get plaintext => text().nullable()();
  TextColumn get ciphertextType => text().nullable()();
  TextColumn get ciphertext => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {messageId};
}
