import 'package:drift/drift.dart';
import 'boards.dart';

class Threads extends Table {
  TextColumn get threadId => text()();
  TextColumn get boardId => text().references(Boards, #boardId)();
  TextColumn get title => text()();
  TextColumn get authorId => text()();

  /// Public poll definition carried by the signed thread operation. This stores
  /// options and optional close time only; voter identities and ballots never
  /// belong in the device database.
  TextColumn get pollJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {threadId};
}
