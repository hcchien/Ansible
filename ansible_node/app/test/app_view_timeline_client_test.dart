import 'dart:convert';

import 'package:ansible_node/services/app_view_timeline_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'posts the follow set and parses the AppView timeline response',
    () async {
      Map<String, dynamic>? sentBody;
      final client = AppViewTimelineClient(
        baseUrl: 'https://appview.example/',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://appview.example/api/v1/timeline',
          );
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'log_id': 9,
                  'op_id': 'op-1',
                  'author_did': 'did:key:alice-legacy',
                  'canonical_author_did': 'did:key:alice',
                  'author_display_name': 'Alice',
                  'author_handle': 'alice.elix.cool',
                  'entity_type': 'murmur',
                  'entity_id': 'm1',
                  'visibility': 'public',
                  'created_at': '2026-06-05T00:00:00.000000Z',
                  'reaction_count': 3,
                  'comment_count': 2,
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

      final page = await client.fetch(
        dids: ['did:key:alice'],
        cursor: 20,
        limit: 50,
      );

      expect(sentBody?['dids'], ['did:key:alice']);
      expect(sentBody?['cursor'], 20);
      expect(sentBody?['limit'], 50);
      expect(page.items, hasLength(2));
      expect(page.items.first.entityType, 'murmur');
      expect(page.items.first.authorDid, 'did:key:alice-legacy');
      expect(page.items.first.canonicalAuthorDid, 'did:key:alice');
      expect(page.items.first.authorDisplayName, 'Alice');
      expect(page.items.first.authorHandle, 'alice.elix.cool');
      expect(page.items.first.payload['body'], 'hi');
      expect(page.items.first.reactionCount, 3);
      expect(page.items.first.commentCount, 2);
      expect(page.items.first.createdAt, isNotNull);
      expect(page.items[1].boardId, 'board-1');
      expect(page.items[1].threadId, 'thread-1');
      expect(page.nextCursor, 8);
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'fetchBoardExternal sends the protocol header and parses items',
    () async {
      String? sentProtocolHeader;
      final client = AppViewTimelineClient(
        baseUrl: 'https://appview.example/',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/boards/board-1/external');
          expect(request.url.queryParameters['cursor'], 'c1');
          expect(request.url.queryParameters['limit'], '25');
          sentProtocolHeader = request.headers['x-ansible-protocol'];
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'items': [
                  {
                    'log_id': 42,
                    'op_id': 'op-ext-1',
                    'board_id': 'board-1',
                    'content': '哈囉 from the fediverse',
                    'created_at': '2026-06-10T00:00:00.000000Z',
                    'external_actor_uri': 'https://g0v.social/users/alice',
                    'external_instance': 'g0v.social',
                    'compliance_level': 'compatible',
                    'reputation_tier': 'external_unverified',
                    'external': true,
                    'origin': 'activitypub',
                  },
                  {
                    'log_id': 41,
                    'op_id': 'op-ext-2',
                    'board_id': 'board-1',
                    'content': 'second',
                    'external_actor_uri': 'https://mstdn.example/users/bob',
                    'external_instance': 'mstdn.example',
                    'compliance_level': 'unknown',
                    'origin': 'activitypub',
                  },
                ],
                'next_cursor': 'c2',
                'has_more': true,
              }),
            ),
            200,
          );
        }),
      );

      final page = await client.fetchBoardExternal(
        'board-1',
        cursor: 'c1',
        limit: 25,
      );

      expect(sentProtocolHeader, isNotNull);
      expect(page.items, hasLength(2));
      final first = page.items.first;
      expect(first.opId, 'op-ext-1');
      expect(first.content, '哈囉 from the fediverse');
      expect(first.externalInstance, 'g0v.social');
      expect(first.complianceLevel, 'compatible');
      expect(first.isCompatible, isTrue);
      expect(first.reputationTier, 'external_unverified');
      expect(first.actorHandle, '@alice@g0v.social');
      expect(first.createdAt, isNotNull);
      expect(page.items[1].isCompatible, isFalse);
      expect(page.items[1].reputationTier, 'external_unverified');
      expect(page.nextCursor, 'c2');
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'fetchExplore requests the public feed and parses timeline items',
    () async {
      final client = AppViewTimelineClient(
        baseUrl: 'https://appview.example/',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/explore');
          expect(request.url.queryParameters['cursor'], '40');
          expect(request.url.queryParameters['limit'], '12');
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'author_did': 'did:key:newcomer',
                  'entity_type': 'murmur',
                  'entity_id': 'm-new',
                  'visibility': 'public',
                  'created_at': '2026-07-21T00:00:00Z',
                  'payload': {'body': 'A changing home feed'},
                },
              ],
              'next_cursor': 39,
              'has_more': true,
            }),
            200,
          );
        }),
      );

      final page = await client.fetchExplore(cursor: 40, limit: 12);

      expect(page.items.single.entityId, 'm-new');
      expect(page.items.single.payload['body'], 'A changing home feed');
      expect(page.nextCursor, 39);
      expect(page.hasMore, isTrue);
    },
  );
}
