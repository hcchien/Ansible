import 'package:ansible_node/services/handle_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('encodes a DID exactly once when resolving its handle', () async {
    late Uri requested;
    final resolver = HandleResolver(
      baseUrl: 'https://relay.example/base',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"did":"did:elix:abc","handle":"alice.elix.cool"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect(await resolver.handleFor('did:elix:abc'), 'alice.elix.cool');
    expect(requested.pathSegments, [
      'base',
      'api',
      'v1',
      'identity',
      'handle',
      'did:elix:abc',
    ]);
    expect(requested.toString(), isNot(contains('%253A')));
  });

  test('keeps an author value that is already a handle', () async {
    var requests = 0;
    final resolver = HandleResolver(
      baseUrl: 'https://relay.example',
      client: MockClient((request) async {
        requests += 1;
        return http.Response('', 500);
      }),
    );

    expect(await resolver.handleFor('@alice.elix.cool'), 'alice.elix.cool');
    expect(requests, 0);
  });
}
