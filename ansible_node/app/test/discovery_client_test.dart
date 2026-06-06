import 'dart:convert';

import 'package:ansible_node/services/discovery_client.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  DiscoveryClient build(
    Future<http.Response> Function(http.Request) handler,
  ) =>
      DiscoveryClient(
        appViewBaseUrl: 'https://appview.test/',
        relayBaseUrl: 'https://relay.test/',
        client: MockClient((req) async => handler(req)),
      );

  test('suggestFollows hits the AppView with reader + parses items', () async {
    String? path;
    Map<String, String>? query;
    final client = build((req) async {
      path = req.url.path;
      query = req.url.queryParameters;
      return http.Response(
        jsonEncode({
          'items': [
            {
              'did': 'did:key:bob',
              'display_name': 'Bob',
              'follower_count': 9,
              'mutual_count': 1,
              'reason': 'followed_by_people_you_follow',
            }
          ]
        }),
        200,
      );
    });

    final items = await client.suggestFollows(readerDid: 'did:key:me', limit: 5);

    expect(path, '/api/v1/suggest/follows');
    expect(query?['reader'], 'did:key:me');
    expect(items.single.did, 'did:key:bob');
    expect(items.single.mutualCount, 1);
    expect(items.single.label, 'Bob');
  });

  test('search fans out to AppView (people+posts) and relay (boards)', () async {
    final hosts = <String>[];
    final client = build((req) async {
      hosts.add('${req.url.host}${req.url.path}');
      if (req.url.host == 'appview.test') {
        return http.Response(
          jsonEncode({
            'actors': [
              {'did': 'did:key:alice', 'handle': 'alice.example'}
            ],
            'posts': [
              {
                'entity_type': 'murmur',
                'entity_id': 'm1',
                'author_did': 'did:key:alice',
                'payload': {'body': 'hello elixir'},
              }
            ],
          }),
          200,
        );
      }
      // relay board search
      return http.Response(
        jsonEncode({
          'boards': [
            {'hosted_board_id': 'elixir', 'title': 'Elixir', 'tags': ['lang']}
          ]
        }),
        200,
      );
    });

    final results = await client.search(query: 'elixir', limit: 10);

    expect(results.actors.single.did, 'did:key:alice');
    expect(results.posts.single.body, 'hello elixir');
    expect(results.boards.single.title, 'Elixir');
    expect(hosts, containsAll(['appview.test/api/v1/search', 'relay.test/api/v1/discover/boards']));
  });

  test('empty query returns empty results without any HTTP call', () async {
    var called = false;
    final client = build((req) async {
      called = true;
      return http.Response('{}', 200);
    });

    final results = await client.search(query: '   ');
    expect(results.actors, isEmpty);
    expect(results.boards, isEmpty);
    expect(called, isFalse);
  });

  test('suggestFollows returns empty when AppView base URL is not configured', () async {
    final client = DiscoveryClient(
      appViewBaseUrl: '',
      relayBaseUrl: 'https://relay.test/',
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    expect(await client.suggestFollows(readerDid: 'did:key:me'), isEmpty);
  });
}
