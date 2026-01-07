
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_ap/ansible_ap.dart';

class ActorHandler {
  final UserRepository userRepository;

  ActorHandler({required this.userRepository});

  Router get router {
    final router = Router();
    router.get('/<username>', _handleActor);
    return router;
  }

  Future<Response> _handleActor(Request request, String username) async {
    final user = await userRepository.getByUsername(username);
    if (user == null) {
      return Response.notFound('User not found');
    }

    final scheme = request.requestedUri.scheme;
    final host = request.requestedUri.host;
    final port = request.requestedUri.port;
    final baseUrl = '$scheme://$host${(port == 80 || port == 443) ? '' : ':$port'}';
    final userUrl = '$baseUrl/api/v1/users/$username';

    final person = Person(
      id: userUrl,
      preferredUsername: username,
      name: user.displayName,
      summary: 'Ansible user',
      inbox: '$baseUrl/api/v1/inbox', // Shared inbox for now
      outbox: '$userUrl/outbox',
      publicKey: {
        'id': '$userUrl#main-key',
        'owner': userUrl,
        'publicKeyPem': '-----BEGIN PUBLIC KEY-----\nTODO_VIRTUAL_KEY\n-----END PUBLIC KEY-----'
      },
      context: [
        'https://www.w3.org/ns/activitystreams',
        'https://w3id.org/security/v1',
      ],
    );

    return Response.ok(
      jsonEncode(person.toJson()),
      headers: {'content-type': 'application/activity+json'},
    );
  }
}
