import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/screens/content_detail_screen.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:ansible_node/services/handle_resolver.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/screens/user_profile_screen.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'detail merges AppView engagement with local rows using canonical DIDs',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await tester.runAsync(db.close);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await db.close();
      });
      const contentId = 'content-1';
      const localDid = 'did:elix:local-legacy';
      await DriftReactionRepository(db).create(
        Reaction(
          id: 'local-reaction',
          userId: localDid,
          targetType: TargetType.thread,
          targetId: contentId,
          reactionType: ReactionType.thumbsUp,
          createdAt: DateTime.utc(2026, 8, 29),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ContentDetailScreen(
            db: db,
            localDid: localDid,
            contentId: contentId,
            authorDid: 'did:elix:author',
            body: 'Body',
            opsDispatchService: OpsDispatchService(
              repository: DriftOpsQueueRepository(db),
            ),
            onFlushPendingOps: () async {},
            appViewBaseUrl: '',
            threadFetcher: ({required threadId}) async {
              expect(threadId, contentId);
              return AppViewTimelinePage(
                items: [
                  AppViewTimelineItem(
                    entityType: 'reaction',
                    entityId: 'remote-copy-of-local-reaction',
                    authorDid: localDid,
                    canonicalAuthorDid: 'did:elix:local-current',
                    payload: {
                      'targetId': contentId,
                      'targetType': 'thread',
                      'reactionType': 'thumbsUp',
                    },
                  ),
                  AppViewTimelineItem(
                    entityType: 'reaction',
                    entityId: 'remote-reaction',
                    authorDid: 'did:elix:remote',
                    canonicalAuthorDid: 'did:elix:remote',
                    payload: {
                      'targetId': contentId,
                      'targetType': 'thread',
                      'reactionType': 'thumbsUp',
                    },
                  ),
                  AppViewTimelineItem(
                    entityType: 'comment',
                    entityId: 'comment-1',
                    createdAt: DateTime(2026, 9, 6, 13, 4),
                    authorDid: 'did:elix:commenter-1',
                    payload: {'content': 'First'},
                  ),
                  AppViewTimelineItem(
                    entityType: 'comment',
                    entityId: 'comment-2',
                    authorDid: 'did:elix:commenter-2',
                    payload: {'content': 'Second'},
                  ),
                ],
              );
            },
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      final reactions = find.byKey(const Key('content_detail_reactions'));
      final comments = find.byKey(const Key('content_detail_comments'));
      expect(reactions, findsOneWidget);
      expect(comments, findsOneWidget);
      final reactionLabels = tester
          .widgetList<Text>(
            find.descendant(of: reactions, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();
      final commentLabels = tester
          .widgetList<Text>(
            find.descendant(of: comments, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();
      expect(reactionLabels, contains('👍 2'));
      expect(
        find.byKey(const ValueKey('comment_reactions_comment-1')),
        findsOneWidget,
      );
      expect(commentLabels, contains('2'));
      expect(find.text('2026-09-06 13:04'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      await tester.runAsync(db.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('typing @ opens the comment picker and replaces the trigger', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.runAsync(db.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await db.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ContentDetailScreen(
          db: db,
          localDid: 'did:elix:local',
          contentId: 'content-mention',
          authorDid: 'did:elix:author',
          body: 'Body',
          opsDispatchService: OpsDispatchService(
            repository: DriftOpsQueueRepository(db),
          ),
          onFlushPendingOps: () async {},
          appViewBaseUrl: '',
          mentionSearch: (query) async {
            expect(query, 'ali');
            return const [
              DiscoveredActor(
                did: 'did:plc:alice',
                handle: 'alice.elix.cool',
                displayName: 'Alice',
              ),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('comment_composer_field')),
      'Hello @',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mention_search_field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('mention_search_field')),
      'ali',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mention_actor_did:plc:alice')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('comment_composer_field')),
    );
    expect(field.controller!.text, 'Hello @Alice ');
    await tester.runAsync(db.close);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'legacy mentionDids render as a styled profile link to the resolved DID',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await tester.runAsync(db.close);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await db.close();
      });
      final handleResolver = HandleResolver(
        baseUrl: 'https://relay.example',
        client: MockClient(
          (_) async => http.Response('{"handle":"alice.elix.cool"}', 200),
        ),
      );
      final profileResolver = PublicProfileResolver(
        baseUrl: 'https://appview.example',
        handleResolver: handleResolver,
        client: MockClient(
          (_) async => http.Response(
            '{"display_name":"Alice","handle":"alice.elix.cool"}',
            200,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ContentDetailScreen(
            db: db,
            localDid: 'did:elix:local',
            contentId: 'content-linked-mention',
            authorDid: 'did:elix:author',
            body: 'Body',
            opsDispatchService: OpsDispatchService(
              repository: DriftOpsQueueRepository(db),
            ),
            onFlushPendingOps: () async {},
            appViewBaseUrl: '',
            mentionProfileResolver: profileResolver,
            threadFetcher: ({required threadId}) async =>
                const AppViewTimelinePage(
                  items: [
                    AppViewTimelineItem(
                      entityType: 'comment',
                      entityId: 'comment-with-mention',
                      authorDid: 'did:elix:commenter',
                      payload: {
                        'content': 'Hello @Alice',
                        'mentionDids': ['did:elix:alice'],
                      },
                    ),
                  ],
                ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      final link = find.byKey(
        const ValueKey('mention_profile_did:elix:alice_0'),
      );
      expect(link, findsOneWidget);
      final label = tester.widget<Text>(
        find.descendant(of: link, matching: find.text('@Alice')),
      );
      expect(label.style?.color, AnsibleDesign.accent);
      expect(label.style?.fontWeight, FontWeight.w700);
      expect(label.style?.decoration, TextDecoration.underline);

      await tester.tap(link);
      await tester.pumpAndSettle();
      final profile = tester.widget<UserProfileScreen>(
        find.byType(UserProfileScreen),
      );
      expect(profile.did, 'did:elix:alice');
      expect(profile.displayName, 'Alice');
      await tester.runAsync(db.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
