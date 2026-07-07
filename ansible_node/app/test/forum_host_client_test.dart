import 'dart:convert';

import 'package:ansible_node/services/forum_host_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchBoardModerationState parses the public state lists', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'http://relay.local/api/v1/forum-host/boards/hosted-1/moderation-state',
        );

        return http.Response(
          jsonEncode({
            'removed_posts': [
              {'target_ref': 'post-1', 'reason_code': 'spam'},
              {'target_ref': 'post-2', 'reason_code': 'harassment'},
            ],
            'locked_threads': [
              {'thread_id': 'thread-1', 'reason_code': 'off_topic'},
            ],
          }),
          200,
        );
      }),
    );

    final state = await client.fetchBoardModerationState('hosted-1');

    expect(state.removedPosts, hasLength(2));
    expect(state.removedPosts.first.targetRef, 'post-1');
    expect(state.removedPosts.first.reasonCode, 'spam');
    expect(state.lockedThreads, hasLength(1));
    expect(state.lockedThreads.single.targetRef, 'thread-1');
    expect(state.lockedThreads.single.reasonCode, 'off_topic');
  });

  test('fetchBoardModerationState tolerates empty/malformed lists', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'removed_posts': [
              {'target_ref': '', 'reason_code': 'spam'},
              {'reason_code': 'spam'},
            ],
            'locked_threads': null,
          }),
          200,
        ),
      ),
    );

    final state = await client.fetchBoardModerationState('hosted-1');

    expect(state.removedPosts, isEmpty);
    expect(state.lockedThreads, isEmpty);
  });

  test('fetchBoardModerationState surfaces unknown_board errors', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'unknown_board'}), 404),
      ),
    );

    await expectLater(
      client.fetchBoardModerationState('missing'),
      throwsA(
        isA<ForumHostException>().having(
          (e) => e.error,
          'error',
          'unknown_board',
        ),
      ),
    );
  });

  test('getHostInfo reads Forum Host metadata', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local/root',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'http://relay.local/root/api/v1/forum-host',
        );

        return http.Response(
          jsonEncode({
            'forum_host_id': 'host-local-dev',
            'display_name': 'Local Forum Host',
            'server_kind': 'ansibleForumHost',
            'capabilities': {'create_boards': true},
          }),
          200,
        );
      }),
    );

    final host = await client.getHostInfo();

    expect(host['forum_host_id'], 'host-local-dev');
    expect(host['server_kind'], 'ansibleForumHost');
  });

  test(
    'getHostInfo ignores base URL query and fragment for endpoint',
    () async {
      final client = ForumHostClient(
        baseUrl: 'http://relay.local/root?token=x#section',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://relay.local/root/api/v1/forum-host',
          );

          return http.Response(
            jsonEncode({
              'forum_host_id': 'host-local-dev',
              'display_name': 'Local Forum Host',
              'server_kind': 'ansibleForumHost',
            }),
            200,
          );
        }),
      );

      final host = await client.getHostInfo();

      expect(host['forum_host_id'], 'host-local-dev');
    },
  );

  test('listHostedBoards reads host-owned boards', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/forum-host/boards');

        return http.Response(
          jsonEncode({
            'boards': [
              {
                'hosted_board_id': 'general',
                'canonical_board_uri': 'https://forum.example/boards/general',
                'slug': 'general',
                'title': 'General',
              },
            ],
          }),
          200,
        );
      }),
    );

    final boards = await client.listHostedBoards();

    expect(boards, hasLength(1));
    expect(
      boards.single['canonical_board_uri'],
      'https://forum.example/boards/general',
    );
  });

  test('listBoardsCreatedBy hits the created-by endpoint with an encoded DID',
      () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        // The DID's colons must be percent-encoded into the path segment.
        expect(
          request.url.path,
          '/api/v1/forum-host/boards/created-by/did%3Aplc%3Aalice',
        );

        return http.Response(
          jsonEncode({
            'boards': [
              {
                'hosted_board_id': 'fifa2026',
                'canonical_board_uri': 'https://forum.example/boards/fifa2026',
                'slug': 'fifa2026',
                'title': 'FIFA2026',
              },
            ],
          }),
          200,
        );
      }),
    );

    final boards = await client.listBoardsCreatedBy('did:plc:alice');

    expect(boards, hasLength(1));
    expect(boards.single['hosted_board_id'], 'fifa2026');
  });

  test('getHostInfo throws status exception for malformed non-2xx body', () {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        return http.Response('<html>unavailable</html>', 503);
      }),
    );

    expect(
      client.getHostInfo(),
      throwsA(
        isA<ForumHostException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.body, 'body', isEmpty),
      ),
    );
  });

  test('getHostInfo preserves parsed non-2xx JSON body', () {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        return http.Response(jsonEncode({'error': 'host_offline'}), 503);
      }),
    );

    expect(
      client.getHostInfo(),
      throwsA(
        isA<ForumHostException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.error, 'error', 'host_offline')
            .having(
              (error) => error.body,
              'body',
              containsPair('error', 'host_offline'),
            ),
      ),
    );
  });

  test('createHostedBoard posts signed create-board intent', () async {
    final createdAt = DateTime.utc(2026, 6, 2, 10);
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/forum-host/boards');
        expect(request.headers['content-type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['type'], 'io.trisaura.forum.createBoard');
        expect(body['version'], 1);
        expect(body['intent_id'], 'intent-1');
        expect(body['author_did'], 'did:key:z6MkUser');
        expect(body['target_forum_host'], 'http://relay.local');
        expect(body['action'], 'create_board');
        expect(body['created_at'], '2026-06-02T10:00:00.000Z');
        expect(body['expires_at'], '2026-06-02T10:05:00.000Z');
        expect(body['signature'], 'sig-hex');
        expect((body['board'] as Map<String, dynamic>).keys.toList(), [
          'description',
          'title',
        ]);
        expect(body['board']['description'], 'Open discussion');
        expect(body['board']['title'], 'General');

        return http.Response(
          jsonEncode({
            'hosted_board_id': 'general',
            'canonical_board_uri': 'http://relay.local/boards/general',
            'slug': 'general',
            'title': 'General',
          }),
          201,
        );
      }),
    );

    final board = await client.createHostedBoard(
      CreateHostedBoardIntent(
        intentId: 'intent-1',
        authorDid: 'did:key:z6MkUser',
        targetForumHost: 'http://relay.local',
        signature: 'sig-hex',
        title: 'General',
        description: 'Open discussion',
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
    );

    expect(board['hosted_board_id'], 'general');
    expect(board['canonical_board_uri'], 'http://relay.local/boards/general');
  });

  test(
    'createHostedBoard throws status exception for malformed non-2xx body',
    () {
      final client = ForumHostClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          return http.Response('<html>invalid board</html>', 400);
        }),
      );

      expect(
        client.createHostedBoard(_testCreateBoardIntent()),
        throwsA(
          isA<ForumHostException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.body, 'body', isEmpty),
        ),
      );
    },
  );

  test('updateHostedBoard posts the signed update intent to the board path',
      () async {
    final createdAt = DateTime.utc(2026, 7, 7, 10);
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/forum-host/boards/fifa2026/update');
        expect(request.headers['content-type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['type'], 'io.trisaura.forum.updateBoard');
        expect(body['version'], 1);
        expect(body['action'], 'update_board');
        expect(body['board_id'], 'fifa2026');
        expect(body['intent_id'], 'intent-2');
        expect(body['author_did'], 'did:key:z6MkUser');
        expect(body['signature'], 'sig-hex');
        expect(body['board'], {
          'description': '',
          'posting_policy': {'min_post_tier': 'verified_human'},
          'title': 'Renamed',
        });

        return http.Response(
          jsonEncode({
            'hosted_board_id': 'fifa2026',
            'canonical_board_uri': 'http://relay.local/boards/fifa2026',
            'slug': 'fifa2026',
            'title': 'Renamed',
            'posting_policy': {'min_post_tier': 'verified_human'},
          }),
          200,
        );
      }),
    );

    final board = await client.updateHostedBoard(
      UpdateHostedBoardIntent(
        intentId: 'intent-2',
        authorDid: 'did:key:z6MkUser',
        targetForumHost: 'http://relay.local',
        signature: 'sig-hex',
        boardId: 'fifa2026',
        title: 'Renamed',
        description: '',
        postingPolicy: const {'min_post_tier': 'verified_human'},
        createdAt: createdAt,
        expiresAt: expiresAt,
      ),
    );

    expect(board['hosted_board_id'], 'fifa2026');
    expect(board['title'], 'Renamed');
  });

  test('updateHostedBoard surfaces relay error codes', () {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'not_board_creator'}), 403),
      ),
    );

    expect(
      client.updateHostedBoard(
        UpdateHostedBoardIntent(
          intentId: 'intent-3',
          authorDid: 'did:key:z6MkOther',
          targetForumHost: 'http://relay.local',
          signature: 'sig-hex',
          boardId: 'fifa2026',
          title: 'Hijack',
          createdAt: DateTime.utc(2026, 7, 7, 10),
          expiresAt: DateTime.utc(2026, 7, 7, 10, 5),
        ),
      ),
      throwsA(
        isA<ForumHostException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.error, 'error', 'not_board_creator'),
      ),
    );
  });

  test('UpdateHostedBoardIntent canonicalPayload uses signed-intent order', () {
    final createdAt = DateTime.utc(2026, 7, 7, 10);
    final expiresAt = createdAt.add(const Duration(minutes: 5));

    final payload = UpdateHostedBoardIntent.canonicalPayload(
      intentId: 'intent-2',
      authorDid: 'did:key:z6MkUser',
      targetForumHost: 'http://relay.local',
      boardId: 'fifa2026',
      title: 'Renamed',
      description: 'New description',
      postingPolicy: const {'min_post_tier': 'verified_human'},
      createdAt: createdAt,
      expiresAt: expiresAt,
    );

    expect(payload.keys.toList(), [
      'action',
      'author_did',
      'board',
      'board_id',
      'created_at',
      'expires_at',
      'intent_id',
      'target_forum_host',
      'type',
      'version',
    ]);
    expect((payload['board'] as Map<String, Object?>).keys.toList(), [
      'description',
      'posting_policy',
      'title',
    ]);
    expect(
      jsonEncode(payload),
      '{"action":"update_board","author_did":"did:key:z6MkUser","board":{"description":"New description","posting_policy":{"min_post_tier":"verified_human"},"title":"Renamed"},"board_id":"fifa2026","created_at":"2026-07-07T10:00:00.000Z","expires_at":"2026-07-07T10:05:00.000Z","intent_id":"intent-2","target_forum_host":"http://relay.local","type":"io.trisaura.forum.updateBoard","version":1}',
    );
  });

  test('UpdateHostedBoardIntent omits absent fields from the board map', () {
    final payload = UpdateHostedBoardIntent.canonicalPayload(
      intentId: 'intent-2',
      authorDid: 'did:key:z6MkUser',
      targetForumHost: 'http://relay.local',
      boardId: 'fifa2026',
      title: 'Renamed',
      createdAt: DateTime.utc(2026, 7, 7, 10),
      expiresAt: DateTime.utc(2026, 7, 7, 10, 5),
    );

    expect(payload['board'], {'title': 'Renamed'});
  });

  test('CreateHostedBoardIntent canonicalPayload uses signed-intent order', () {
    final createdAt = DateTime.utc(2026, 6, 2, 10);
    final expiresAt = createdAt.add(const Duration(minutes: 5));

    final payload = CreateHostedBoardIntent.canonicalPayload(
      intentId: 'intent-1',
      authorDid: 'did:key:z6MkUser',
      targetForumHost: 'http://relay.local',
      title: 'General',
      description: 'Open discussion',
      createdAt: createdAt,
      expiresAt: expiresAt,
    );

    expect(payload.keys.toList(), [
      'action',
      'author_did',
      'board',
      'created_at',
      'expires_at',
      'intent_id',
      'target_forum_host',
      'type',
      'version',
    ]);
    expect((payload['board'] as Map<String, Object?>).keys.toList(), [
      'description',
      'title',
    ]);
    expect(
      jsonEncode(payload),
      '{"action":"create_board","author_did":"did:key:z6MkUser","board":{"description":"Open discussion","title":"General"},"created_at":"2026-06-02T10:00:00.000Z","expires_at":"2026-06-02T10:05:00.000Z","intent_id":"intent-1","target_forum_host":"http://relay.local","type":"io.trisaura.forum.createBoard","version":1}',
    );
  });
}

CreateHostedBoardIntent _testCreateBoardIntent() {
  final createdAt = DateTime.utc(2026, 6, 2, 10);
  return CreateHostedBoardIntent(
    intentId: 'intent-1',
    authorDid: 'did:key:z6MkUser',
    targetForumHost: 'http://relay.local',
    signature: 'sig-hex',
    title: 'General',
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 5)),
  );
}
