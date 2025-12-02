import 'dart:convert';
import 'package:ansible_store/ansible_store.dart' as entity;
import 'package:ansible_store/src/repositories/in_memory/in_memory_thread_repository.dart';
import 'package:ansible_store/src/repositories/thread_repository.dart';
import 'package:ansible_relay/src/controllers/thread_controller.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ThreadController', () {
    late ThreadRepository repo;
    late ThreadController controller;

    setUp(() {
      repo = InMemoryThreadRepository();
      controller = ThreadController(repo);
    });

    test('List threads returns empty list initially', () async {
      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/')),
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(jsonDecode(body), isEmpty);
    });

    test('Create thread', () async {
      final threadData = {
        'id': 't1',
        'boardId': 'b1',
        'title': 'Thread 1',
        'authorId': 'user-123',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: jsonEncode(threadData),
        ),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body);
      expect(json['id'], 't1');
      expect(json['title'], 'Thread 1');

      final stored = await repo.getById('t1');
      expect(stored, isNotNull);
      expect(stored!.title, 'Thread 1');
    });

    test('Get thread by ID', () async {
      await repo.create(entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1',
        authorId: 'user-123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/t1')),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body);
      expect(json['id'], 't1');
    });

    test('List threads by boardId', () async {
      await repo.create(entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'T1',
        authorId: 'user-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await repo.create(entity.Thread(
        id: 't2',
        boardId: 'b2',
        title: 'T2',
        authorId: 'user-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/?boardId=b1')),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body) as List;
      expect(json.length, 1);
      expect(json[0]['id'], 't1');
    });

    test('Update thread', () async {
      await repo.create(entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1',
        authorId: 'user-123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final updateData = {
        'boardId': 'b1',
        'title': 'Thread 1 Updated',
        'authorId': 'user-123',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final response = await controller.router.call(
        Request(
          'PUT',
          Uri.parse('http://localhost/t1'),
          body: jsonEncode(updateData),
        ),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body);
      expect(json['title'], 'Thread 1 Updated');

      final stored = await repo.getById('t1');
      expect(stored!.title, 'Thread 1 Updated');
    });

    test('Delete thread', () async {
      await repo.create(entity.Thread(
        id: 't1',
        boardId: 'b1',
        title: 'Thread 1',
        authorId: 'user-123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final response = await controller.router.call(
        Request('DELETE', Uri.parse('http://localhost/t1')),
      );

      expect(response.statusCode, 200);

      final stored = await repo.getById('t1');
      expect(stored, isNull);
    });
  });
}
