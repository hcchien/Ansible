import 'dart:convert';

import 'package:ansible_node/screens/hosted_boards_screen.dart';
import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// "My hosted boards" management screen: lists the boards this DID created on
// each active Forum Host and edits them through signed update_board intents.
// Widget tests assert zh-Hant copy because the test locale falls back to
// zh-Hant (uiCopy returns zh when no AppLocalizations is installed).
void main() {
  const did = 'did:plc:alice';

  late AppDatabase db;
  late DriftRemoteNodeRepository remoteNodeRepo;
  late DriftHostedBoardRepository hostedBoardRepo;
  late DriftBoardRepository boardRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remoteNodeRepo = DriftRemoteNodeRepository(db);
    hostedBoardRepo = DriftHostedBoardRepository(db);
    boardRepo = DriftBoardRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedHost() async {
    final now = DateTime.now();
    await remoteNodeRepo.create(
      RemoteNode(
        id: 'host1',
        name: 'relay.local',
        url: 'http://relay.local',
        createdAt: now,
        updatedAt: now,
        isActive: true,
      ),
    );
  }

  Map<String, dynamic> hostedBoard({
    String title = 'FIFA2026',
    Map<String, dynamic> postingPolicy = const {},
    Map<String, dynamic>? accessPolicy,
  }) {
    return {
      'hosted_board_id': 'fifa2026',
      'slug': 'fifa2026',
      'canonical_board_uri': 'http://relay.local/boards/fifa2026',
      'title': title,
      'description': 'World cup talk',
      'posting_policy': postingPolicy,
      if (accessPolicy != null) 'access_policy': accessPolicy,
    };
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required http.Client Function() httpClientFactory,
    List<String>? signedPayloads,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HostedBoardsScreen(
          did: did,
          remoteNodeRepo: remoteNodeRepo,
          hostedBoardRepo: hostedBoardRepo,
          boardRepo: boardRepo,
          clientFactory: (baseUrl) =>
              ForumHostClient(baseUrl: baseUrl, client: httpClientFactory()),
          signIntent: (message) async {
            signedPayloads?.add(utf8.decode(message));
            return 'deadbeef';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state when no hosted boards exist', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      httpClientFactory: () => MockClient(
        (_) async => http.Response(jsonEncode({'boards': []}), 200),
      ),
    );

    expect(find.text('我主持的看板'), findsOneWidget);
    expect(find.text('你還沒有主持任何看板'), findsOneWidget);
    expect(find.text('建立看板後，你可以在這裡編輯標題、描述與發文資格。'), findsOneWidget);
  });

  testWidgets('lists the boards this DID created on active hosts', (
    tester,
  ) async {
    await seedHost();
    await pumpScreen(
      tester,
      httpClientFactory: () => MockClient((request) async {
        expect(
          request.url.path,
          '/api/v1/forum-host/boards/created-by/did%3Aplc%3Aalice',
        );
        return http.Response(
          jsonEncode({
            'boards': [
              hostedBoard(postingPolicy: {'min_post_tier': 'verified_human'}),
            ],
          }),
          200,
        );
      }),
    );

    expect(find.text('FIFA2026'), findsOneWidget);
    expect(find.textContaining('World cup talk'), findsOneWidget);
    expect(find.textContaining('僅限真人驗證發文'), findsOneWidget);
  });

  testWidgets('shows a retry error state when every host fails', (
    tester,
  ) async {
    await seedHost();
    await pumpScreen(
      tester,
      httpClientFactory: () => MockClient(
        (_) async => http.Response(jsonEncode({'error': 'boom'}), 500),
      ),
    );

    expect(find.text('無法載入你主持的看板，請檢查網路後再試一次。'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
  });

  testWidgets('restores a pending policy effective time from history', (
    tester,
  ) async {
    await seedHost();
    final effectiveAt = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 25));
    await pumpScreen(
      tester,
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.endsWith('/policy-history')) {
          return http.Response(
            jsonEncode({
              'versions': [
                {
                  'policy_hash': 'pending-hash',
                  'effective_at': effectiveAt.toIso8601String(),
                  'superseded_at': null,
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'boards': [
              hostedBoard(accessPolicy: {'version': 1}),
            ],
          }),
          200,
        );
      }),
    );

    expect(find.textContaining('政策變更待生效'), findsOneWidget);
  });

  testWidgets(
    'editing a board submits a signed update intent and refreshes the '
    'local projection cache',
    (tester) async {
      await seedHost();
      final now = DateTime.now();
      await boardRepo.create(
        Board(
          id: 'host1_fifa2026',
          slug: 'fifa2026',
          title: 'FIFA2026',
          description: 'World cup talk',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await hostedBoardRepo.upsertProjection(
        HostedBoardProjection(
          localBoardId: 'host1_fifa2026',
          forumHostId: 'host1',
          hostedBoardId: 'fifa2026',
          canonicalBoardUri: 'http://relay.local/boards/fifa2026',
          remoteSlug: 'fifa2026',
          localSlug: 'fifa2026',
          title: 'FIFA2026',
          description: 'World cup talk',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final updateBodies = <Map<String, dynamic>>[];
      final signedPayloads = <String>[];
      await pumpScreen(
        tester,
        signedPayloads: signedPayloads,
        httpClientFactory: () => MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'boards': [hostedBoard()],
              }),
              200,
            );
          }
          expect(request.url.path, '/api/v1/forum-host/boards/fifa2026/update');
          final body =
              jsonDecode(utf8.decode(request.bodyBytes))
                  as Map<String, dynamic>;
          updateBodies.add(body);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(hostedBoard(title: body['board']['title'] as String)),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await tester.tap(find.text('FIFA2026'));
      await tester.pumpAndSettle();
      expect(find.text('編輯託管看板'), findsOneWidget);
      // Metadata editing is intentionally separate from the versioned access
      // policy editor, so a title change cannot silently change governance.
      expect(find.byKey(const Key('board_audience_mode')), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, 'FIFA 2026 世界盃');
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();

      // Signed update intent hit the board-scoped update endpoint.
      expect(updateBodies, hasLength(1));
      final body = updateBodies.single;
      expect(body['type'], 'io.trisaura.forum.updateBoard');
      expect(body['action'], 'update_board');
      expect(body['board_id'], 'fifa2026');
      expect(body['author_did'], did);
      expect(body['signature'], 'deadbeef');
      expect(body['board']['title'], 'FIFA 2026 世界盃');

      // The signature covered the canonical payload (sans signature).
      expect(signedPayloads, hasLength(1));
      expect(signedPayloads.single, contains('"action":"update_board"'));
      expect(signedPayloads.single, isNot(contains('signature')));

      // Let the rest of the async chain (cache writes → snackbar) finish.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      // Success feedback + refreshed local caches.
      expect(find.textContaining('已更新看板'), findsOneWidget);
      final projection = await hostedBoardRepo.getProjection(
        'host1',
        'fifa2026',
      );
      expect(projection?.title, 'FIFA 2026 世界盃');
      final localBoard = await boardRepo.getById('host1_fifa2026');
      expect(localBoard?.title, 'FIFA 2026 世界盃');
    },
  );

  testWidgets('a rejected update surfaces localized copy, not a raw error', (
    tester,
  ) async {
    await seedHost();
    await pumpScreen(
      tester,
      httpClientFactory: () => MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'boards': [hostedBoard()],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'error': 'not_board_creator'}), 403);
      }),
    );

    await tester.tap(find.text('FIFA2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.textContaining('只有看板建立者可以編輯這個看板'), findsOneWidget);
    expect(find.textContaining('ForumHostException'), findsNothing);
  });
}
