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
import '../schema/remote_nodes.dart';
import '../schema/board_sync_configs.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Boards, Threads, Posts, Reactions, Users, BoardAcl, ActivityLog, RemoteNodes, BoardSyncConfigs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 6) {
        await m.createTable(remoteNodes);
        await m.createTable(boardSyncConfigs);
      }
    },
  );
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
