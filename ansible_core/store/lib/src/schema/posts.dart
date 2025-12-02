import 'package:drift/drift.dart';
import 'threads.dart';
import 'boards.dart';
import 'users.dart';

class Posts extends Table {
  TextColumn get postId => text()();
  TextColumn get threadId => text().references(Threads, #threadId)();
  TextColumn get boardId => text().references(Boards, #boardId)();
  TextColumn get authorId => text().references(Users, #userId)();
  TextColumn get content => text()();
  TextColumn get parentPostId => text().nullable().references(Posts, #postId)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastEditAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {postId};
}
