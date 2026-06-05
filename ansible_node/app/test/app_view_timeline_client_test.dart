import 'dart:convert';

import 'package:ansible_node/services/app_view_timeline_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('posts the follow set and parses the AppView timeline response', () async {
    Map<String, dynamic>? sentBody;
    final client = AppViewTimelineClient(
      baseUrl: 'https://appview.example/',
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://appview.example/api/v1/timeline');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'log_id': 9,
                'op_id': 'op-1',
                'author_did': 'did:key:alice',
                'entity_type': 'murmur',
                'entity_id': 'm1',
                'visibility': 'public',
                'created_at': '2026-06-05T00:00:00.000000Z',
                'payload': {'body': 'hi'},
                'public_key_hex': 'b',
                'reputation_tier': 'verified_human',
              },
              {
                'log_id': 8,
                'op_id': 'op-2',
                'author_did': 'did:key:alice',
                'entity_type': 'post',
                'entity_id': 'p1',
                'board_id': 'board-1',
                'thread_id': 'thread-1',
                'created_at': '2026-06-04T00:00:00.000000Z',
                'payload': {'content': 'a post'},
                'public_key_hex': 'b',
              },
            ],
            'next_cursor': 8,
            'has_more': true,
          }),
          200,
        );
      }),
    );

    final page = await client.fetch(dids: ['did:key:alice'], cursor: 20, limit: 50);

    expect(sentBody?['dids'], ['did:key:alice']);
    expect(sentBody?['cursor'], 20);
    expect(sentBody?['limit'], 50);
    expect(page.items, hasLength(2));
    expect(page.items.first.entityType, 'murmur');
    expect(page.items.first.payload['body'], 'hi');
    expect(page.items.first.createdAt, isNotNull);
    expect(page.items[1].boardId, 'board-1');
    expect(page.items[1].threadId, 'thread-1');
    expect(page.nextCursor, 8);
    expect(page.hasMore, isTrue);
  });
}
