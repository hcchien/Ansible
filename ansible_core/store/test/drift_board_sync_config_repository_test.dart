import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/drift/drift_board_sync_config_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:ansible_store/src/db/app_database.dart';

void main() {
  group('DriftBoardSyncConfigRepository', () {
    late AppDatabase db;
    late DriftBoardSyncConfigRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftBoardSyncConfigRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Create and retrieve BoardSyncConfig', () async {
      final now = DateTime.now();
      final config = entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      );

      await repo.create(config);
      final retrieved = await repo.getById('config-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.remoteNodeId, 'node-1');
      expect(retrieved.boardId, 'board-1');
      expect(retrieved.syncEnabled, isTrue);
    });

    test('Get config by remote and board', () async {
      final now = DateTime.now();
      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));

      final retrieved = await repo.getByRemoteAndBoard('node-1', 'board-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'config-1');
    });

    test('List configs by remote node', () async {
      final now = DateTime.now();

      // Configs for node-1
      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));
      await repo.create(entity.BoardSyncConfig(
        id: 'config-2',
        remoteNodeId: 'node-1',
        boardId: 'board-2',
        syncEnabled: false,
        createdAt: now,
        updatedAt: now,
      ));

      // Config for node-2
      await repo.create(entity.BoardSyncConfig(
        id: 'config-3',
        remoteNodeId: 'node-2',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));

      final node1Configs = await repo.listByRemote('node-1');
      expect(node1Configs.length, 2);
      expect(node1Configs.map((c) => c.id), containsAll(['config-1', 'config-2']));

      final node2Configs = await repo.listByRemote('node-2');
      expect(node2Configs.length, 1);
    });

    test('Get enabled board IDs', () async {
      final now = DateTime.now();

      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));
      await repo.create(entity.BoardSyncConfig(
        id: 'config-2',
        remoteNodeId: 'node-1',
        boardId: 'board-2',
        syncEnabled: false,
        createdAt: now,
        updatedAt: now,
      ));
      await repo.create(entity.BoardSyncConfig(
        id: 'config-3',
        remoteNodeId: 'node-1',
        boardId: 'board-3',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));

      final enabledIds = await repo.getEnabledBoardIds('node-1');
      expect(enabledIds.length, 2);
      expect(enabledIds, containsAll(['board-1', 'board-3']));
      expect(enabledIds, isNot(contains('board-2')));
    });

    test('Toggle sync - enable existing config', () async {
      final now = DateTime.now();
      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: false,
        createdAt: now,
        updatedAt: now,
      ));

      await repo.toggleSync('node-1', 'board-1', true);

      final retrieved = await repo.getByRemoteAndBoard('node-1', 'board-1');
      expect(retrieved!.syncEnabled, isTrue);
    });

    test('Toggle sync - disable existing config', () async {
      final now = DateTime.now();
      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));

      await repo.toggleSync('node-1', 'board-1', false);

      final retrieved = await repo.getByRemoteAndBoard('node-1', 'board-1');
      expect(retrieved!.syncEnabled, isFalse);
    });

    test('Toggle sync - create new config if not exists', () async {
      // No existing config
      var retrieved = await repo.getByRemoteAndBoard('node-1', 'board-1');
      expect(retrieved, isNull);

      await repo.toggleSync('node-1', 'board-1', true);

      retrieved = await repo.getByRemoteAndBoard('node-1', 'board-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.syncEnabled, isTrue);
    });

    test('Update BoardSyncConfig', () async {
      final now = DateTime.now();
      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));

      final updated = entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: false,
        createdAt: now,
        updatedAt: now.add(const Duration(hours: 1)),
      );
      await repo.update(updated);

      final retrieved = await repo.getById('config-1');
      expect(retrieved!.syncEnabled, isFalse);
    });

    test('Delete BoardSyncConfig', () async {
      final now = DateTime.now();
      await repo.create(entity.BoardSyncConfig(
        id: 'config-1',
        remoteNodeId: 'node-1',
        boardId: 'board-1',
        syncEnabled: true,
        createdAt: now,
        updatedAt: now,
      ));

      await repo.delete('config-1');
      final retrieved = await repo.getById('config-1');
      expect(retrieved, isNull);
    });
  });
}
