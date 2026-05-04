import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../schema/boards.dart';
import '../schema/threads.dart';
import '../schema/posts.dart';
import '../schema/reactions.dart';
import '../schema/board_acl.dart';
import '../schema/activity_log.dart';
import '../schema/remote_nodes.dart';
import '../schema/board_sync_configs.dart';
import '../schema/identities.dart';  // DID-based identity (v1.1)
import '../schema/ops_queue.dart';   // Local CRDT Op queue (v1.1 Comp B)

part 'app_database.g.dart';

// Schema v7: dropped Users (passwordHash), added Identities (DID) + OpsQueue (CRDT)
@DriftDatabase(tables: [Boards, Threads, Posts, Reactions, BoardAcl, ActivityLog, RemoteNodes, BoardSyncConfigs, Identities, OpsQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 6) {
        await m.createTable(remoteNodes);
        await m.createTable(boardSyncConfigs);
      }
      if (from < 7) {
        // v7: drop password-based Users; add DID Identities + CRDT OpsQueue
        await m.createTable(identities);
        await m.createTable(opsQueue);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = Directory.current;
    final file = File(p.join(dbFolder.path, 'ansible.db'));
    return NativeDatabase.createInBackground(file);
  });
}
