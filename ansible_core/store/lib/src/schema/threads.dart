import 'package:drift/drift.dart';
import 'boards.dart';

class Threads extends Table {
  TextColumn get threadId => text()();
  TextColumn get boardId => text().references(Boards, #boardId)();
  TextColumn get title => text()();
  TextColumn get authorId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {threadId};
}
