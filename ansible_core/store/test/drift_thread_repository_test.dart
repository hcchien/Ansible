import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/drift/drift_thread_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:ansible_store/src/db/app_database.dart';

void main() {
  group('DriftThreadRepository', () {
    late AppDatabase db;
    late DriftThreadRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftThreadRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Create and retrieve Thread', () async {
      final thread = entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1',
        authorId: 'did:key:123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.create(thread);
      final retrieved = await repo.getById('t1');

      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Thread 1');
      expect(retrieved.boardId, 'b1');
    });

    test('persists public poll definitions without voter data', () async {
      final thread = entity.Thread(
        id: 'poll-1',
        boardId: 'b1',
        title: '下一次聚會？',
        authorId: 'did:key:123',
        poll: {
          'options': [
            {'id': 'option-1', 'label': '週六'},
            {'id': 'option-2', 'label': '週日'},
          ],
          'closes_at': '2026-08-31T00:00:00.000Z',
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.create(thread);

      final retrieved = await repo.getById('poll-1');
      expect(retrieved?.poll?['closes_at'], '2026-08-31T00:00:00.000Z');
      expect(retrieved?.poll?['options'], [
        {'id': 'option-1', 'label': '週六'},
        {'id': 'option-2', 'label': '週日'},
      ]);
    });

    test(
      'persists public poll tally without a voter identity or ballot',
      () async {
        final thread = entity.Thread(
          id: 'poll-results-1',
          boardId: 'b1',
          title: '投票',
          authorId: 'did:key:123',
          poll: {
            'options': [
              {'id': 'a', 'label': 'A'},
              {'id': 'b', 'label': 'B'},
            ],
          },
          pollResults: {
            'options': [
              {'id': 'a', 'label': 'A', 'votes': 3},
              {'id': 'b', 'label': 'B', 'votes': 1},
            ],
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await repo.create(thread);
        final retrieved = await repo.getById(thread.id);
        expect(retrieved?.pollResults?['options'], [
          {'id': 'a', 'label': 'A', 'votes': 3},
          {'id': 'b', 'label': 'B', 'votes': 1},
        ]);
      },
    );

    test('Update Thread', () async {
      final thread = entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1',
        authorId: 'did:key:123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.create(thread);

      final updatedThread = entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1 Updated',
        authorId: 'did:key:123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.update(updatedThread);

      final retrieved = await repo.getById('t1');
      expect(retrieved!.title, 'Thread 1 Updated');
    });

    test('List Threads', () async {
      await repo.create(
        entity.Thread(
          id: 't1',
          boardId: 'b1',
          title: 'T1',
          authorId: 'did:key:1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await repo.create(
        entity.Thread(
          id: 't2',
          boardId: 'b1',
          title: 'T2',
          authorId: 'did:key:1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await repo.create(
        entity.Thread(
          id: 't3',
          boardId: 'b2',
          title: 'T3',
          authorId: 'did:key:1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final allThreads = await repo.list();
      expect(allThreads.length, 3);

      final b1Threads = await repo.list(boardId: 'b1');
      expect(b1Threads.length, 2);
      expect(b1Threads.map((t) => t.id), containsAll(['t1', 't2']));
    });

    test('Delete Thread', () async {
      final thread = entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1',
        authorId: 'did:key:123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.create(thread);

      await repo.delete('t1');

      final retrieved = await repo.getById('t1');
      expect(retrieved, isNotNull);
      expect(retrieved!.isDeleted, isTrue);
    });
  });
}
