import 'dart:convert';
import 'package:ansible_node/screens/public_content_screen.dart';
import 'package:ansible_node/screens/public_browse_screen.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const post = DiscoveredPost(
    entityType: 'murmur',
    entityId: 'm1',
    authorDid: 'did:a',
    payload: {},
  );
  Map<String, dynamic> item(String id, String type, String body) => {
    'entity_type': type,
    'entity_id': id,
    'author_did': 'did:a',
    'sig_verified': true,
    'payload': {'body': body},
  };
  testWidgets(
    'exact public post opens without subscription and preserves content on reply failure',
    (tester) async {
      var failReplies = true;
      var interactions = 0;
      final requests = <Uri>[];
      final client = DiscoveryClient(
        appViewBaseUrl: 'https://unused-viewer.invalid',
        relayBaseUrl: 'https://relay.test',
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.contains('/content/')) {
            return http.Response(
              jsonEncode({'item': item('m1', 'murmur', '完整原文')}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (failReplies) return http.Response('{}', 503);
          return http.Response(
            jsonEncode({
              'items': [item('c1', 'comment', '完整留言')],
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PublicContentScreen(
            post: post,
            client: client,
            onInteract: () => interactions++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('完整原文'),
        findsOneWidget,
        reason:
            tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .toList()
                .toString() +
            requests.toString(),
      );
      expect(find.text('目前無法連線，請重試。'), findsOneWidget);
      expect(requests.every((uri) => uri.host == 'relay.test'), isTrue);
      failReplies = false;
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(find.text('完整留言'), findsOneWidget);
      await tester.tap(find.byTooltip('已驗證作者簽章'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不代表內容為真'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('參與討論'));
      expect(interactions, 1);
    },
  );

  testWidgets(
    'guest search sends text only on explicit search and exposes filtered pagination',
    (tester) async {
      final queries = <String>[];
      final client = DiscoveryClient(
        appViewBaseUrl: '',
        relayBaseUrl: 'https://relay.test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/explore')) {
            return http.Response(
              jsonEncode({
                'items': request.url.queryParameters['cursor'] == null
                    ? []
                    : [item('m1', 'murmur', '後一頁')],
                'has_more': request.url.queryParameters['cursor'] == null,
                'next_cursor': 10,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          queries.add(request.url.queryParameters['q'] ?? '');
          return http.Response('{"posts":[],"actors":[],"boards":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: PublicBrowseScreen(client: client)),
      );
      await tester.pumpAndSettle();
      expect(find.text('沒有符合的公開貼文。'), findsNothing);
      await tester.tap(find.text('載入更多公開貼文'));
      await tester.pumpAndSettle();
      expect(
        find.text('後一頁'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .toList()
            .toString(),
      );
      await tester.enterText(find.byType(TextField), '主動公開查詢');
      await tester.pumpAndSettle();
      expect(queries, isEmpty);
      await tester.tap(find.byTooltip('搜尋'));
      await tester.pumpAndSettle();
      expect(queries, everyElement('主動公開查詢'));
      expect(queries, isNotEmpty);
    },
  );
}
