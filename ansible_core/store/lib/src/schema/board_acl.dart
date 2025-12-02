import 'package:drift/drift.dart';
import 'boards.dart';
import 'users.dart';

class BoardAcl extends Table {
  TextColumn get boardId => text().references(Boards, #boardId)();
  TextColumn get userId => text().references(Users, #userId)();
  BoolColumn get canRead => boolean().withDefault(const Constant(true))();
  BoolColumn get canWrite => boolean().withDefault(const Constant(true))();
  BoolColumn get isAdmin => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {boardId, userId};
}
