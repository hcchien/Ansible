import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/screens/content_detail_screen.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'detail merges AppView engagement with local rows using canonical DIDs',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
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
              return const AppViewTimelinePage(
                items: [
                  AppViewTimelineItem(
                    entityType: 'reaction',
                    entityId: 'remote-copy-of-local-reaction',
                    authorDid: localDid,
                    canonicalAuthorDid: 'did:elix:local-current',
                    payload: {'targetId': contentId, 'targetType': 'thread'},
                  ),
                  AppViewTimelineItem(
                    entityType: 'reaction',
                    entityId: 'remote-reaction',
                    authorDid: 'did:elix:remote',
                    canonicalAuthorDid: 'did:elix:remote',
                    payload: {'targetId': contentId, 'targetType': 'thread'},
                  ),
                  AppViewTimelineItem(
                    entityType: 'comment',
                    entityId: 'comment-1',
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
      expect(reactionLabels, contains('2'));
      expect(commentLabels, contains('2'));
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    },
  );

  testWidgets('typing @ opens the comment picker and replaces the trigger', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

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
    expect(field.controller!.text, 'Hello @alice.elix.cool ');
  });
}
