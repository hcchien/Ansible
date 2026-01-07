
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';

class WebFingerHandler {
  final UserRepository userRepository;

  WebFingerHandler({required this.userRepository});

  Router get router {
    final router = Router();
    router.get('/', _handleWebFinger);
    return router;
  }

  Future<Response> _handleWebFinger(Request request) async {
    final resource = request.url.queryParameters['resource'];
    if (resource == null || !resource.startsWith('acct:')) {
      return Response.badRequest(body: 'Missing or invalid resource param');
    }

    final acct = resource.substring(5);
    final parts = acct.split('@');
    if (parts.isEmpty) {
       return Response.notFound('User not found');
    }
    final username = parts[0];

    final user = await userRepository.getByUsername(username);
    if (user == null) {
      return Response.notFound('User not found');
    }

    final scheme = request.requestedUri.scheme;
    final host = request.requestedUri.host;
    final port = request.requestedUri.port;
    final baseUrl = '$scheme://$host${(port == 80 || port == 443) ? '' : ':$port'}';

    final jrd = {
      'subject': resource,
      'links': [
        {
          'rel': 'self',
          'type': 'application/activity+json',
          'href': '$baseUrl/api/v1/users/$username'
        }
      ]
    };

    return Response.ok(
      jsonEncode(jrd),
      headers: {'content-type': 'application/jrd+json'},
    );
  }
}
