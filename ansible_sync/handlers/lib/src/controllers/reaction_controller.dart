import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';
import '../utils/error_responses.dart';

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
    try {
      final targetType = request.url.queryParameters['targetType'];
      final targetId = request.url.queryParameters['targetId'];

      if (targetType == null || targetId == null) {
        return ErrorResponses.validationError(
          message: 'Missing required query parameters: targetType and targetId',
        );
      }

      final reactions = await _repo.listByTarget(targetType, targetId);
      return Response.ok(
        jsonEncode({'items': reactions.map((r) => r.toJson()).toList()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return ErrorResponses.internalError(message: 'Failed to list reactions: $e');
    }
  }

  Future<Response> _createReaction(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final reaction = Reaction.fromJson(data);
      await _repo.create(reaction);
      return Response.ok(
        jsonEncode(reaction.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return ErrorResponses.internalError(message: 'Failed to create reaction: $e');
    }
  }

  Future<Response> _deleteReaction(Request request, String id) async {
    try {
      await _repo.delete(id);
      return Response.ok(null, headers: {'content-type': 'application/json'});
    } catch (e) {
      return ErrorResponses.internalError(message: 'Failed to delete reaction: $e');
    }
  }
}
