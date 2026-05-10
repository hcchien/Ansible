import 'dart:convert';

import 'package:ansible_node/services/forum_host_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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

  test('createHostedBoard posts signed create-board intent', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/forum-host/boards');
        expect(request.headers['content-type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['intent_id'], 'intent-1');
        expect(body['author_did'], 'did:key:z6MkUser');
        expect(body['signature'], 'sig-hex');
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
      const CreateHostedBoardIntent(
        intentId: 'intent-1',
        authorDid: 'did:key:z6MkUser',
        signature: 'sig-hex',
        title: 'General',
        description: 'Open discussion',
      ),
    );

    expect(board['hosted_board_id'], 'general');
    expect(board['canonical_board_uri'], 'http://relay.local/boards/general');
  });
}
