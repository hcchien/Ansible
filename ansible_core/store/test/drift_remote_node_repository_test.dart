import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/drift/drift_remote_node_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:ansible_store/src/db/app_database.dart';

void main() {
  group('DriftRemoteNodeRepository', () {
    late AppDatabase db;
    late DriftRemoteNodeRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftRemoteNodeRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Create and retrieve RemoteNode', () async {
      final now = DateTime.now();
      final node = entity.RemoteNode(
        id: 'node-1',
        name: 'Test Server',
        url: 'https://relay.example.com',
        accessToken: 'test-token',
        syncCursor: 0,
        createdAt: now,
        updatedAt: now,
        isActive: true,
      );

      await repo.create(node);
      final retrieved = await repo.getById('node-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Test Server');
      expect(retrieved.url, 'https://relay.example.com');
      expect(retrieved.accessToken, 'test-token');
      expect(retrieved.syncCursor, 0);
      expect(retrieved.isActive, isTrue);
    });

    test('Get active RemoteNode', () async {
      final now = DateTime.now();

      // Create inactive node
      await repo.create(entity.RemoteNode(
        id: 'node-inactive',
        name: 'Inactive Server',
        url: 'https://inactive.example.com',
        createdAt: now,
        updatedAt: now,
        isActive: false,
      ));

      // Create active node
      await repo.create(entity.RemoteNode(
        id: 'node-active',
        name: 'Active Server',
        url: 'https://active.example.com',
        createdAt: now,
        updatedAt: now,
        isActive: true,
      ));

      final active = await repo.getActive();
      expect(active, isNotNull);
      expect(active!.id, 'node-active');
      expect(active.isActive, isTrue);
    });

    test('Update RemoteNode', () async {
      final now = DateTime.now();
      final node = entity.RemoteNode(
        id: 'node-1',
        name: 'Original Name',
        url: 'https://original.example.com',
        createdAt: now,
        updatedAt: now,
      );
      await repo.create(node);

      final updated = node.copyWith(
        name: 'Updated Name',
        url: 'https://updated.example.com',
        accessToken: 'new-token',
        updatedAt: now.add(const Duration(hours: 1)),
      );
      await repo.update(updated);

      final retrieved = await repo.getById('node-1');
      expect(retrieved!.name, 'Updated Name');
      expect(retrieved.url, 'https://updated.example.com');
      expect(retrieved.accessToken, 'new-token');
    });

    test('Update sync cursor', () async {
      final now = DateTime.now();
      final node = entity.RemoteNode(
        id: 'node-1',
        name: 'Test Server',
        url: 'https://relay.example.com',
        syncCursor: 0,
        createdAt: now,
        updatedAt: now,
      );
      await repo.create(node);

      final syncTime = DateTime.now().add(const Duration(minutes: 5));
      await repo.updateSyncCursor('node-1', 150, syncTime);

      final retrieved = await repo.getById('node-1');
      expect(retrieved!.syncCursor, 150);
      expect(retrieved.lastSyncAt, isNotNull);
    });

    test('Delete RemoteNode', () async {
      final now = DateTime.now();
      await repo.create(entity.RemoteNode(
        id: 'node-1',
        name: 'Test Server',
        url: 'https://relay.example.com',
        createdAt: now,
        updatedAt: now,
      ));

      await repo.delete('node-1');
      final retrieved = await repo.getById('node-1');
      expect(retrieved, isNull);
    });

    test('List all RemoteNodes', () async {
      final now = DateTime.now();
      await repo.create(entity.RemoteNode(
        id: 'node-1',
        name: 'Server 1',
        url: 'https://server1.example.com',
        createdAt: now,
        updatedAt: now,
      ));
      await repo.create(entity.RemoteNode(
        id: 'node-2',
        name: 'Server 2',
        url: 'https://server2.example.com',
        createdAt: now,
        updatedAt: now,
      ));

      final list = await repo.list();
      expect(list.length, 2);
      expect(list.map((n) => n.id), containsAll(['node-1', 'node-2']));
    });

    test('RemoteNode with null accessToken', () async {
      final now = DateTime.now();
      final node = entity.RemoteNode(
        id: 'node-1',
        name: 'Public Server',
        url: 'https://public.example.com',
        accessToken: null,
        createdAt: now,
        updatedAt: now,
      );

      await repo.create(node);
      final retrieved = await repo.getById('node-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.accessToken, isNull);
    });
  });
}
