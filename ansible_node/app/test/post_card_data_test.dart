import 'package:ansible_node/screens/home/post_card.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment count excludes the opening post', () {
    final now = DateTime.utc(2026, 7, 17);
    Post post(String id) => Post(
      id: id,
      threadId: 'thread-1',
      boardId: 'board-1',
      authorId: 'did:elix:alice',
      content: id,
      createdAt: now,
      updatedAt: now,
      lastEditAt: now,
    );

    expect(replyCountForPosts(const []), 0);
    expect(replyCountForPosts([post('op')]), 0);
    expect(replyCountForPosts([post('op'), post('reply')]), 1);
  });

  testWidgets('share icon opens the injected share sheet with post content', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 7, 17);
    final thread = Thread(
      id: 'thread-1',
      boardId: 'board-1',
      title: 'Title',
      authorId: 'did:elix:alice',
      createdAt: now,
      updatedAt: now,
    );
    String? sharedText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            db: db,
            authorDid: 'did:elix:local',
            opsDispatchService: OpsDispatchService(
              repository: InMemoryOpsQueueRepository(),
            ),
            onFlushPendingOps: () async {},
            shareSheet: (text, {sharePositionOrigin}) async {
              expect(sharePositionOrigin, isNotNull);
              sharedText = text;
            },
            data: PostCardData(
              thread: thread,
              category: 'General',
              title: thread.title,
              content: 'Original post body',
              author: thread.authorId,
              board: 'General',
              timeAgo: 'now',
              reactions: const {'👍': 0},
              comments: 0,
              reacted: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(sharedText, 'Original post body');
    expect(find.byTooltip('分享貼文'), findsOneWidget);
  });
}
