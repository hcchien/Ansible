import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../schema/boards.dart';
import '../schema/threads.dart';
import '../schema/posts.dart';
import '../schema/reactions.dart';
import '../schema/users.dart';
import '../schema/board_acl.dart';
import '../schema/activity_log.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Boards, Threads, Posts, Reactions, Users, BoardAcl, ActivityLog])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 5;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Use application documents directory for persistent storage
    final dbFolder = Directory.current;
    final file = File(p.join(dbFolder.path, 'soapbox.db'));
    print('Database path: ${file.path}');
    return NativeDatabase.createInBackground(file);
  });
}
