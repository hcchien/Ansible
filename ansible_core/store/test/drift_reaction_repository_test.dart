import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/drift/drift_reaction_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:ansible_store/src/db/app_database.dart';

void main() {
  group('DriftReactionRepository', () {
    late AppDatabase db;
    late DriftReactionRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftReactionRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Create and list reactions by target', () async {
      final reaction1 = entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.happy,
        createdAt: DateTime.now(),
      );

      final reaction2 = entity.Reaction(
        id: 'r2',
        userId: 'user-2',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.thumbsUp,
        createdAt: DateTime.now(),
      );

      await repo.create(reaction1);
      await repo.create(reaction2);

      final reactions = await repo.listByTarget('thread', 't1');
      expect(reactions.length, 2);
      expect(reactions.map((r) => r.id), containsAll(['r1', 'r2']));
    });

    test('Get reaction by user and target', () async {
      final reaction = entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.post,
        targetId: 'p1',
        reactionType: entity.ReactionType.angry,
        createdAt: DateTime.now(),
      );

      await repo.create(reaction);

      final retrieved = await repo.getByUserAndTarget('user-1', 'post', 'p1');
      expect(retrieved, isNotNull);
      expect(retrieved!.reactionType, entity.ReactionType.angry);
    });

    test('Delete reaction', () async {
      final reaction = entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.sad,
        createdAt: DateTime.now(),
      );

      await repo.create(reaction);
      await repo.delete('r1');

      final reactions = await repo.listByTarget('thread', 't1');
      expect(reactions, isEmpty);
    });

    test('Replace existing reaction', () async {
      final reaction1 = entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.happy,
        createdAt: DateTime.now(),
      );

      final reaction2 = entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.angry,
        createdAt: DateTime.now(),
      );

      await repo.create(reaction1);
      await repo.create(reaction2);

      final retrieved = await repo.getByUserAndTarget('user-1', 'thread', 't1');
      expect(retrieved!.reactionType, entity.ReactionType.angry);
    });
  });
}
