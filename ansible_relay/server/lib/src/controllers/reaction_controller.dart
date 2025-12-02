import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';

class ReactionController {
  final ReactionRepository _repo;

  ReactionController(this._repo);

  Router get router {
    final router = Router();

    router.get('/', _listReactions);
    router.post('/', _createReaction);
    router.delete('/<id>', _deleteReaction);

    return router;
  }

  Future<Response> _listReactions(Request request) async {
    final targetType = request.url.queryParameters['targetType'];
    final targetId = request.url.queryParameters['targetId'];

    if (targetType == null || targetId == null) {
      return Response.badRequest(
        body: 'Missing required query parameters: targetType and targetId',
      );
    }

    final reactions = await _repo.listByTarget(targetType, targetId);
    return Response.ok(
      jsonEncode(reactions.map((r) => r.toJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _createReaction(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    final reaction = Reaction.fromJson(data);
    await _repo.create(reaction);
    return Response.ok(
      jsonEncode(reaction.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _deleteReaction(Request request, String id) async {
    await _repo.delete(id);
    return Response.ok(null, headers: {'content-type': 'application/json'});
  }
}
