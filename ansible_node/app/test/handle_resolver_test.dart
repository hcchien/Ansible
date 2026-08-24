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

  test('prefers a published display name over the handle', () async {
    final fallback = HandleResolver(
      baseUrl: 'https://relay.example',
      client: MockClient((_) async => http.Response('', 404)),
    );
    final resolver = PublicProfileResolver(
      baseUrl: 'https://appview.example/base',
      handleResolver: fallback,
      client: MockClient((request) async {
        expect(request.url.pathSegments, [
          'base',
          'api',
          'v1',
          'profiles',
          'did:elix:alice',
        ]);
        return http.Response(
          '{"did":"did:elix:alice","display_name":"Alice","handle":"alice.elix.cool"}',
          200,
        );
      }),
    );

    expect(
      (await resolver.profileFor('did:elix:alice'))?.preferredLabel,
      'Alice',
    );
  });

  test('formats a handle distinctly when no display name is published', () {
    expect(
      const PublicAuthorProfile(handle: 'hcchien').preferredLabel,
      '@hcchien',
    );
  });
}
