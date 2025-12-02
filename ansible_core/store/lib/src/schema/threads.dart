import 'package:drift/drift.dart';
import 'boards.dart';
import 'users.dart';

class Threads extends Table {
  TextColumn get threadId => text()();
  TextColumn get boardId => text().references(Boards, #boardId)();
  TextColumn get title => text()();
  TextColumn get authorId => text().references(Users, #userId)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {threadId};
}
