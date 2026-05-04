import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../schema/activity_log.dart';
import '../schema/board_acl.dart';
import '../schema/board_sync_configs.dart';
import '../schema/boards.dart';
import '../schema/identities.dart';
import '../schema/ops_queue.dart';
import '../schema/posts.dart';
import '../schema/reactions.dart';
import '../schema/remote_nodes.dart';
import '../schema/threads.dart';
import '../schema/wallet_credential_payloads.dart';
import '../schema/wallet_credentials.dart';
import '../schema/wallet_presentations.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Boards,
    Threads,
    Posts,
    Reactions,
    BoardAcl,
    ActivityLog,
    RemoteNodes,
    BoardSyncConfigs,
    Identities,
    OpsQueue,
    WalletCredentials,
    WalletCredentialPayloads,
    WalletPresentations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 6) {
        await _createTableIfMissing(m, remoteNodes);
        await _createTableIfMissing(m, boardSyncConfigs);
      }
      if (from < 8) {
        await _createTableIfMissing(m, walletCredentials);
        await _createTableIfMissing(m, walletCredentialPayloads);
        await _createTableIfMissing(m, walletPresentations);
      }
      if (from < 9) {
        await _createTableIfMissing(m, identities);
        await _createTableIfMissing(m, opsQueue);
      }
      await _addColumnIfMissing(
        m,
        boardSyncConfigs,
        boardSyncConfigs.retentionDays,
      );
    },
  );

  Future<void> _createTableIfMissing(
    Migrator migrator,
    TableInfo<Table, Object?> table,
  ) async {
    final exists = await customSelect(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      variables: [
        const Variable<String>('table'),
        Variable<String>(table.actualTableName),
      ],
    ).getSingleOrNull();
    if (exists == null) {
      await migrator.createTable(table);
    }
  }

  Future<void> _addColumnIfMissing(
    Migrator migrator,
    TableInfo<Table, Object?> table,
    GeneratedColumn<Object> column,
  ) async {
    final exists = await customSelect(
      'SELECT 1 FROM pragma_table_info(?) WHERE name = ? LIMIT 1',
      variables: [
        Variable<String>(table.actualTableName),
        Variable<String>(column.$name),
      ],
    ).getSingleOrNull();
    if (exists == null) {
      await migrator.addColumn(table, column);
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = Directory.current;
    final file = File(p.join(dbFolder.path, 'ansible.db'));
    return NativeDatabase.createInBackground(file);
  });
}
