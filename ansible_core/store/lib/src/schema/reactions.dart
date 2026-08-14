import 'package:drift/drift.dart';

class Reactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get targetType => text()(); // 'thread' or 'post'
  TextColumn get targetId => text()();
  TextColumn get reactionType =>
      text()(); // 'happy', 'sad', 'thumbsUp', 'angry'
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  /// A person can have one active reaction per target. This is deliberately a
  /// local invariant too: sync retries or a second device must not inflate a
  /// displayed count while the Relay rejects the duplicate remotely.
  @override
  List<Set<Column>> get uniqueKeys => [
    {userId, targetType, targetId},
  ];
}
