import 'package:drift/drift.dart';

class MessengerConversations extends Table {
  TextColumn get conversationId => text()();
  TextColumn get peerDid => text()();
  TextColumn get title => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastMessageAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {conversationId};
}
