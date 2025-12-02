import 'dart:convert';
import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/in_memory/in_memory_reaction_repository.dart';
import 'package:ansible_store/src/repositories/reaction_repository.dart';
import 'package:ansible_sync/ansible_sync.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ReactionController', () {
    late ReactionRepository repo;
    late ReactionController controller;

    setUp(() {
      repo = InMemoryReactionRepository();
      controller = ReactionController(repo);
    });

    test('Create reaction', () async {
      final reactionData = {
        'id': 'r1',
        'userId': 'user-1',
        'targetType': 'thread',
        'targetId': 't1',
        'reactionType': 'happy',
        'createdAt': DateTime.now().toIso8601String(),
      };

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: jsonEncode(reactionData),
        ),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['id'], 'r1');
      expect(json['reactionType'], 'happy');
    });

    test('List reactions by target', () async {
      await repo.create(entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.happy,
        createdAt: DateTime.now(),
      ));
      await repo.create(entity.Reaction(
        id: 'r2',
        userId: 'user-2',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.thumbsUp,
        createdAt: DateTime.now(),
      ));

      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/?targetType=thread&targetId=t1')),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['items'], isA<List>());
      expect((json['items'] as List).length, 2);
    });

    test('Delete reaction', () async {
      await repo.create(entity.Reaction(
        id: 'r1',
        userId: 'user-1',
        targetType: entity.TargetType.thread,
        targetId: 't1',
        reactionType: entity.ReactionType.angry,
        createdAt: DateTime.now(),
      ));

      final response = await controller.router.call(
        Request('DELETE', Uri.parse('http://localhost/r1')),
      );

      expect(response.statusCode, 200);

      final reactions = await repo.listByTarget('thread', 't1');
      expect(reactions, isEmpty);
    });

    test('List reactions with missing parameters returns 400', () async {
      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/')),
      );

      expect(response.statusCode, 400);
    });
  });
}
