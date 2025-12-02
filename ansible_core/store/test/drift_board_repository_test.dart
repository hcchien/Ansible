import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/drift/drift_board_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:ansible_store/src/db/app_database.dart';

void main() {
  group('DriftBoardRepository', () {
    late AppDatabase db;
    late DriftBoardRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftBoardRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Create and retrieve Board', () async {
      final now = DateTime.now();
      final board = entity.Board(
        id: 'board-1',
        slug: 'tech',
        title: 'Technology',
        description: 'All things technology',
        createdAt: now,
        updatedAt: now,
      );

      await repo.create(board);
      final retrieved = await repo.getById('board-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Technology');
      expect(retrieved.slug, 'tech');
      expect(retrieved.isDeleted, isFalse);
    });

    test('Update Board', () async {
      final createdAt = DateTime.now();
      final board = entity.Board(
        id: 'board-1',
        slug: 'tech',
        title: 'Technology',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      await repo.create(board);

      final updatedBoard = entity.Board(
        id: 'board-1',
        slug: 'tech-updated',
        title: 'Technology Updated',
        description: 'New desc',
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(hours: 1)),
        isDeleted: true,
      );
      await repo.update(updatedBoard);

      final retrieved = await repo.getById('board-1');
      expect(retrieved!.title, 'Technology Updated');
      expect(retrieved.slug, 'tech-updated');
      expect(retrieved.description, 'New desc');
      expect(retrieved.isDeleted, isTrue);
    });

    test('List Boards', () async {
      final now = DateTime.now();
      await repo.create(
        entity.Board(
          id: 'b1',
          slug: 'b1',
          title: 'B1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repo.create(
        entity.Board(
          id: 'b2',
          slug: 'b2',
          title: 'B2',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final list = await repo.list();
      expect(list.length, 2);
      expect(list.map((b) => b.id), containsAll(['b1', 'b2']));
    });
  });
}
