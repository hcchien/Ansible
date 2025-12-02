import 'package:drift/drift.dart';
import 'users.dart';

class Reactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #userId)();
  TextColumn get targetType => text()(); // 'thread' or 'post'
  TextColumn get targetId => text()();
  TextColumn get reactionType => text()(); // 'happy', 'sad', 'thumbsUp', 'angry'
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
