import 'dart:convert';

import 'package:ansible_node/services/relay_discovery_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchDiscovery reads Relay bootstrap catalog with base path', () async {
    final client = RelayDiscoveryClient(
      baseUrl: 'http://relay.local/root/',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'http://relay.local/root/api/v1/discovery',
        );
        return http.Response(
          jsonEncode({
            'version': 1,
            'relay': {
              'server_kind': 'elixRelay',
              'origin': 'http://relay.local',
              'capabilities': {
                'forum_host_discovery': true,
                'relay_announcements': true,
                'web_sessions': true,
              },
            },
            'announcements': [
              {
                'announcement_id': 'relay-status',
                'owner_kind': 'relay',
                'title': 'Relay online',
                'body': 'Discovery ready',
                'severity': 'info',
              },
            ],
            'featured_forum_hosts': [
              {
                'forum_host_id': 'host-local-dev',
                'display_name': 'Local Forum Host',
                'forum_host_url': 'http://relay.local',
                'constitution_compliance': 'unknown',
              },
            ],
            'featured_boards': [
              {
                'board_id': 42,
                'hosted_board_id': 'general',
                'title': 'General',
                'description': 'Start here',
                'forum_host_url': 'http://relay.local',
                'canonical_board_uri': 'http://relay.local/boards/general',
                'constitution_compliance': 'unknown',
                'tags': ['intro'],
                'language': 'en',
              },
            ],
            'cache': {'max_age_seconds': 300},
          }),
          200,
        );
      }),
    );

    final discovery = await client.fetchDiscovery();

    expect(discovery.version, 1);
    expect(discovery.relay.serverKind, 'elixRelay');
    expect(discovery.relay.origin, 'http://relay.local');
    expect(discovery.relay.capabilities['web_sessions'], true);
    expect(discovery.announcements.single.ownerKind, 'relay');
    expect(
      discovery.featuredForumHosts.single.constitutionCompliance,
      'unknown',
    );
    expect(discovery.featuredBoards.single.hostedBoardId, '42');
    expect(discovery.featuredBoards.single.description, 'Start here');
    expect(discovery.featuredBoards.single.tags, ['intro']);
    expect(discovery.featuredBoards.single.language, 'en');
    expect(discovery.cache?.maxAgeSeconds, 300);
  });

  test(
    'fetchDiscovery ignores base URL query and fragment for endpoint',
    () async {
      final client = RelayDiscoveryClient(
        baseUrl: 'http://relay.local/root?token=x#section',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://relay.local/root/api/v1/discovery',
          );
          return http.Response(
            jsonEncode({
              'version': 1,
              'relay': {
                'server_kind': 'elixRelay',
                'origin': 'http://relay.local',
              },
            }),
            200,
          );
        }),
      );

      final discovery = await client.fetchDiscovery();

      expect(discovery.version, 1);
    },
  );

  test('fetchDiscovery defaults and preserves compliance metadata', () async {
    final client = RelayDiscoveryClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/discovery');
        return http.Response(
          jsonEncode({
            'version': 1,
            'relay': {
              'server_kind': 'elixRelay',
              'origin': 'http://relay.local',
            },
            'featured_forum_hosts': [
              {
                'forum_host_id': 'missing-compliance',
                'display_name': 'Missing Compliance',
                'forum_host_url': 'http://missing.local',
              },
              {
                'forum_host_id': 'compatible-host',
                'display_name': 'Compatible Host',
                'forum_host_url': 'http://compatible.local',
                'constitution_compliance': 'compatible',
              },
            ],
            'featured_boards': [
              {
                'hosted_board_id': 'general',
                'title': 'General',
                'forum_host_url': 'http://missing.local',
                'canonical_board_uri': 'http://missing.local/boards/general',
              },
              {
                'hosted_board_id': 'local-news',
                'title': 'Local News',
                'forum_host_url': 'http://compatible.local',
                'canonical_board_uri':
                    'http://compatible.local/boards/local-news',
                'constitution_compliance': 'constitution_compliant',
              },
            ],
          }),
          200,
        );
      }),
    );

    final discovery = await client.fetchDiscovery();

    expect(discovery.announcements, isEmpty);
    expect(
      discovery.featuredForumHosts.first.constitutionCompliance,
      'unknown',
    );
    expect(
      discovery.featuredForumHosts.last.constitutionCompliance,
      'compatible',
    );
    expect(discovery.featuredBoards.first.constitutionCompliance, 'unknown');
    expect(
      discovery.featuredBoards.last.constitutionCompliance,
      'constitution_compliant',
    );
    expect(discovery.cache, isNull);
  });

  test('fetchDiscovery throws status exception for malformed non-2xx body', () {
    final client = RelayDiscoveryClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        return http.Response('<html>not found</html>', 404);
      }),
    );

    expect(
      client.fetchDiscovery(),
      throwsA(
        isA<RelayDiscoveryException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.body, 'body', isEmpty),
      ),
    );
  });

  test('fetchDiscovery preserves parsed non-2xx JSON body', () {
    final client = RelayDiscoveryClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        return http.Response(jsonEncode({'error': 'discovery_disabled'}), 503);
      }),
    );

    expect(
      client.fetchDiscovery(),
      throwsA(
        isA<RelayDiscoveryException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.body,
              'body',
              containsPair('error', 'discovery_disabled'),
            ),
      ),
    );
  });
}
