import 'dart:convert';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_sync/ansible_sync.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('BoardController', () {
    late InMemoryBoardRepository repo;
    late BoardController controller;

    setUp(() {
      repo = InMemoryBoardRepository();
      controller = BoardController(repo);
    });

    test('List boards returns empty list initially', () async {
      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/')),
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['items'], isEmpty);
    });

    test('Create board', () async {
      final now = DateTime.now().toIso8601String();
      final boardData = {
        'id': 'b1',
        'slug': 'tech',
        'title': 'Technology',
        'description': 'All things tech',
        'createdAt': now,
        'updatedAt': now,
      };

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: jsonEncode(boardData),
        ),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body);
      expect(json['id'], 'b1');
      expect(json['title'], 'Technology');

      final stored = await repo.getById('b1');
      expect(stored, isNotNull);
      expect(stored!.title, 'Technology');
    });

    test('Get board by ID', () async {
      final now = DateTime.now();
      await repo.create(Board(
        id: 'b1',
        slug: 'tech',
        title: 'Technology',
        createdAt: now,
        updatedAt: now,
      ));

      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/b1')),
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      final json = jsonDecode(body);
      expect(json['id'], 'b1');
    });

    test('Get non-existent board returns 404', () async {
      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/b999')),
      );

      expect(response.statusCode, 404);
    });
  });
}
