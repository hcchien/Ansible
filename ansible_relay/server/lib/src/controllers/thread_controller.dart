import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';

class ThreadController {
  final ThreadRepository _repo;

  ThreadController(this._repo);

  Router get router {
    final router = Router();

    router.get('/', _listThreads);
    router.post('/', _createThread);
    router.get('/<id>', _getThread);
    router.put('/<id>', _updateThread);
    router.delete('/<id>', _deleteThread);

    return router;
  }

  Future<Response> _listThreads(Request request) async {
    final boardId = request.url.queryParameters['boardId'];
    final threads = await _repo.list(boardId: boardId);
    return Response.ok(
      jsonEncode(threads.map((t) => t.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _createThread(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    final thread = Thread.fromJson(data);
    await _repo.create(thread);
    return Response.ok(
      jsonEncode(thread.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _getThread(Request request, String id) async {
    final thread = await _repo.getById(id);
    if (thread == null) {
      return Response.notFound('Thread not found');
    }
    return Response.ok(
      jsonEncode(thread.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _updateThread(Request request, String id) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    // Ensure ID in body matches URL
    data['id'] = id;
    final thread = Thread.fromJson(data);
    await _repo.update(thread);
    return Response.ok(
      jsonEncode(thread.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _deleteThread(Request request, String id) async {
    await _repo.delete(id);
    return Response.ok(null, headers: {'content-type': 'application/json'});
  }
}
