import 'package:ansible_node/screens/home/post_card.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/theme/elix_screen_style.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Paper feed cards stay light when the system is dark', () {
    expect(
      postCardBackgroundColor(
        screenStyle: ElixScreenStyle.paper,
        systemBrightness: Brightness.dark,
      ),
      AnsibleDesign.paperWhite,
    );
    expect(
      postCardBackgroundColor(
        screenStyle: ElixScreenStyle.ink,
        systemBrightness: Brightness.light,
      ),
      AnsibleDesign.darkPaperWhite,
    );
  });

  test('post detail preserves the source board reading style', () {
    expect(postDetailScreenStyle(ElixScreenStyle.paper), ElixScreenStyle.paper);
    expect(postDetailScreenStyle(ElixScreenStyle.ink), ElixScreenStyle.ink);
    expect(
      postDetailScreenStyle(ElixScreenStyle.system),
      ElixScreenStyle.system,
    );
  });

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

  test('discussion and standalone cards use their detail reaction targets', () {
    final now = DateTime.utc(2026, 8, 29);
    final thread = Thread(
      id: 'thread-1',
      boardId: 'board-1',
      title: 'Discussion',
      authorId: 'did:elix:alice',
      createdAt: now,
      updatedAt: now,
    );
    final openingPost = Post(
      id: 'opening-post',
      threadId: thread.id,
      boardId: thread.boardId,
      authorId: thread.authorId,
      content: 'Opening',
      createdAt: now,
      updatedAt: now,
      lastEditAt: now,
    );
    PostCardData card({required bool openableThread, Post? opening}) =>
        PostCardData(
          thread: thread,
          category: 'General',
          title: thread.title,
          content: opening?.content ?? 'Standalone',
          author: thread.authorId,
          board: 'General',
          timeAgo: 'now',
          reactions: const {'👍': 0},
          comments: 0,
          reacted: false,
          openingPost: opening,
          openableThread: openableThread,
        );

    final discussion = card(openableThread: true, opening: openingPost);
    expect(discussion.reactionTargetType, TargetType.post);
    expect(discussion.reactionTargetId, openingPost.id);

    final standalone = card(openableThread: false);
    expect(standalone.reactionTargetType, TargetType.thread);
    expect(standalone.reactionTargetId, thread.id);
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

  testWidgets('reaction action does not open the post thread', (tester) async {
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
    var openedContent = false;

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
            onOpenContent: (_) => openedContent = true,
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
              openableThread: false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(openedContent, isFalse);
    expect(find.text('👍'), findsOneWidget);
  });

  testWidgets('discussion author and board are separate navigation targets', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 7, 17);
    final thread = Thread(
      id: 'thread-nav',
      boardId: 'board-nav',
      title: 'Navigation',
      authorId: 'did:elix:alice',
      createdAt: now,
      updatedAt: now,
    );
    String? openedAuthor;
    String? openedBoard;

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
            onOpenAuthor: (did) => openedAuthor = did,
            onOpenBoard: (boardId) => openedBoard = boardId,
            data: PostCardData(
              thread: thread,
              category: 'General',
              title: thread.title,
              content: 'Body',
              author: thread.authorId,
              authorDisplayName: 'Alice',
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

    await tester.tap(find.byKey(const Key('post_card_author_thread-nav')));
    expect(openedAuthor, 'did:elix:alice');
    expect(openedBoard, isNull);

    openedAuthor = null;
    await tester.tap(find.byKey(const Key('post_card_board_thread-nav')));
    expect(openedBoard, 'board-nav');
    expect(openedAuthor, isNull);
  });

  testWidgets('hosted discussion share uses the Web frontend URL', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 7, 17);
    await DriftHostedBoardRepository(db).upsertProjection(
      HostedBoardProjection(
        localBoardId: 'board-1',
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        canonicalBoardUri: 'https://relay.example/boards/hosted-1',
        remoteSlug: 'general',
        localSlug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      ),
    );
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

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(
      sharedText,
      'https://forum.elix.cool/boards/hosted-1/threads/thread-1',
    );
  });
}
