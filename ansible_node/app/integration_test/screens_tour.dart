import 'package:ansible_node/l10n/app_localizations.dart';
import 'package:ansible_node/screens/content_detail_screen.dart';
import 'package:ansible_node/screens/home/home_bottom_bar.dart';
import 'package:ansible_node/screens/home/home_types.dart';
import 'package:ansible_node/screens/home/post_card.dart';
import 'package:ansible_node/screens/home/timeline_board.dart';
import 'package:ansible_node/screens/notifications_screen.dart';
import 'package:ansible_node/screens/onboarding_intro_screen.dart';
import 'package:ansible_node/screens/post_composer_screen.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/services/handle_resolver.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/theme/elix_screen_style.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-simulator screenshot tour. Mounts each real screen with seeded data and
/// captures a PNG per screen (written to design/current-screens/ by the driver).
/// Rendered in zh-Hant to match the Elix design language. Every screen is
/// mounted directly with hand-seeded data so the run never waits on the network.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const me = 'did:plc:tris';
  const mira = 'did:plc:mira';
  const kr = 'did:plc:kr';
  final now = DateTime(2026, 6, 30, 9, 41);

  // Friendly bylines/avatars offline (no relay in the harness).
  HandleResolver.shared.seed(me, 'tris.elix.cool');
  HandleResolver.shared.seed(mira, 'mira.elix.cool');
  HandleResolver.shared.seed(kr, 'kr.elix.cool');

  Widget harness(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AnsibleDesign.theme(),
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    );
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  AppDatabase freshDb() => AppDatabase(NativeDatabase.memory());

  OpsDispatchService ops(AppDatabase db) =>
      OpsDispatchService(repository: DriftOpsQueueRepository(db));

  PostCardData feedCard({
    required String id,
    required String author,
    required String title,
    required String content,
    required String timeAgo,
    int reacts = 0,
    int comments = 0,
    bool signed = false,
    String tier = 'basic',
  }) {
    return PostCardData(
      thread: Thread(
        id: id,
        boardId: 'board-philosophy',
        title: title,
        authorId: author,
        createdAt: now,
        updatedAt: now,
      ),
      category: '哲學',
      title: title,
      content: content,
      author: author,
      board: '哲學',
      timeAgo: timeAgo,
      reactions: {'👍': reacts},
      comments: comments,
      reacted: false,
      signatureVerified: signed,
      authorTier: tier,
    );
  }

  testWidgets('A · onboarding intro', (tester) async {
    await tester.pumpWidget(harness(OnboardingIntroScreen(onContinue: () {})));
    await shoot(tester, 'a01_onboarding_welcome');
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await shoot(tester, 'a02_onboarding_promise');
  });

  testWidgets('B · timeline feed', (tester) async {
    final db = freshDb();
    addTearDown(db.close);
    final posts = [
      feedCard(
        id: 'p1',
        author: mira,
        title: '我們在重建什麼樣的網路？',
        content: '關於默許可見、身分自主、社群健康的長對話。便利往往是監控偽裝的禮物。',
        timeAgo: '1 小時',
        reacts: 12,
        comments: 23,
        signed: true,
        tier: 'verified_human',
      ),
      feedCard(
        id: 'p2',
        author: kr,
        title: '',
        content: '刪掉社群帳號的第 47 天。安靜得令人不安，但也第一次聽見自己的想法。',
        timeAgo: '12 分',
        reacts: 4,
        comments: 7,
        signed: true,
      ),
    ];
    await tester.pumpWidget(
      harness(
        Scaffold(
          backgroundColor: AnsibleDesign.paper,
          body: SafeArea(
            child: TimelineBoardView(
              db: db,
              did: me,
              loading: false,
              followingPosts: posts,
              opsDispatchService: ops(db),
              onFlushPendingOps: () async {},
            ),
          ),
        ),
      ),
    );
    await shoot(tester, 'b01_timeline_feed');
  });

  testWidgets('F · bottom nav', (tester) async {
    final db = freshDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      harness(
        Scaffold(
          backgroundColor: AnsibleDesign.paper,
          body: SafeArea(
            bottom: false,
            child: TimelineBoardView(
              db: db,
              did: me,
              loading: false,
              followingPosts: [
                feedCard(
                  id: 'p1',
                  author: mira,
                  title: '我們在重建什麼樣的網路？',
                  content: '關於默許可見、身分自主、社群健康的長對話。',
                  timeAgo: '1 小時',
                  reacts: 12,
                  comments: 23,
                  signed: true,
                  tier: 'verified_human',
                ),
              ],
              opsDispatchService: ops(db),
              onFlushPendingOps: () async {},
            ),
          ),
          bottomNavigationBar: HomeBottomBar(
            selectedBoard: HomeBoard.timeline,
            onSelectBoard: (_) {},
            onCompose: () {},
            onNotifications: () {},
            onProfile: () {},
            boardActive: true,
            unreadCount: 3,
          ),
        ),
      ),
    );
    await shoot(tester, 'f01_bottom_nav');
  });

  testWidgets('E15 · single board', (tester) async {
    final db = freshDb();
    addTearDown(db.close);
    await DriftBoardRepository(db).create(
      Board(
        id: 'board-philosophy',
        slug: 'philosophy',
        title: 'philosophy',
        description: '我們在重建什麼樣的網路？關於默許可見、身分自主、社群健康的長對話。',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final threadRepo = DriftThreadRepository(db);
    final postRepo = DriftPostRepository(db);
    Future<void> seedThread(
      String id,
      String author,
      String title,
      String body,
      DateTime created,
    ) async {
      await threadRepo.create(
        Thread(
          id: id,
          boardId: 'board-philosophy',
          title: title,
          authorId: author,
          createdAt: created,
          updatedAt: created,
        ),
      );
      await postRepo.create(
        Post(
          id: 'post-$id',
          threadId: id,
          boardId: 'board-philosophy',
          authorId: author,
          content: body,
          createdAt: created,
          updatedAt: created,
          lastEditAt: created,
          signatureVerified: true,
        ),
      );
    }

    await seedThread(
      't1',
      mira,
      '我們在重建什麼樣的網路？',
      '一個關於信任地形的開場。',
      now.subtract(const Duration(hours: 1)),
    );
    // A couple of replies on t1 so it reads "進行中" with a 最後回應 time.
    for (final r in [
      (id: 'r1', author: kr, mins: 40),
      (id: 'r2', author: me, mins: 15),
    ]) {
      await postRepo.create(
        Post(
          id: r.id,
          threadId: 't1',
          boardId: 'board-philosophy',
          authorId: r.author,
          content: '回應內容',
          createdAt: now.subtract(Duration(minutes: r.mins)),
          updatedAt: now.subtract(Duration(minutes: r.mins)),
          lastEditAt: now.subtract(Duration(minutes: r.mins)),
          signatureVerified: true,
        ),
      );
    }
    await seedThread(
      't2',
      kr,
      '便利往往是監控偽裝的禮物',
      '我們交出了什麼，又換回了什麼？',
      now.subtract(const Duration(minutes: 12)),
    );
    await seedThread(
      't3',
      me,
      '刪掉社群帳號的第 47 天',
      '安靜得令人不安。',
      now.subtract(const Duration(days: 2)),
    );

    final board = (await DriftBoardRepository(db).list()).first;
    await tester.pumpWidget(
      harness(
        ThreadsListScreen(
          db: db,
          board: board,
          localDid: me,
          opsDispatchService: ops(db),
          onFlushPendingOps: () async {},
        ),
      ),
    );
    await shoot(tester, 'e15_single_board');

    // Dark (Ink) variant — verifies E15 follows the board's Paper/Ink choice.
    await tester.pumpWidget(
      harness(
        ThreadsListScreen(
          db: db,
          board: board,
          localDid: me,
          opsDispatchService: ops(db),
          onFlushPendingOps: () async {},
          screenStyle: ElixScreenStyle.ink,
        ),
      ),
    );
    await shoot(tester, 'e15_single_board_dark');
  });

  testWidgets('content detail', (tester) async {
    final db = freshDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      harness(
        ContentDetailScreen(
          db: db,
          localDid: me,
          contentId: 'c1',
          authorDid: mira,
          title: '我們在重建什麼樣的網路？',
          timeAgo: '1 小時',
          body:
              '我們在重建什麼樣的網路？一個沒有默許監控、身分由自己保管的網路。'
              '便利往往是監控偽裝成的禮物——我們交出了座標，換回了推薦。',
          opsDispatchService: ops(db),
          onFlushPendingOps: () async {},
        ),
      ),
    );
    await shoot(tester, 'd01_content_detail');
  });

  testWidgets('compose', (tester) async {
    await tester.pumpWidget(
      harness(const PostComposerScreen(authorDid: me)),
    );
    await shoot(tester, 'c01_compose');
  });

  testWidgets('notifications', (tester) async {
    final db = freshDb();
    addTearDown(db.close);
    final notifRepo = DriftNotificationRepository(db);
    await notifRepo.upsertByDedupKey(
      AppNotification(
        id: 'n1',
        type: NotificationType.replyToPost,
        actorDid: mira,
        targetRef: 'post-1',
        threadId: 't1',
        boardId: 'board-philosophy',
        createdAt: now.subtract(const Duration(minutes: 8)),
        dedupKey: 'n1',
      ),
    );
    await notifRepo.upsertByDedupKey(
      AppNotification(
        id: 'n2',
        type: NotificationType.newFollower,
        actorDid: kr,
        targetRef: kr,
        createdAt: now.subtract(const Duration(hours: 3)),
        dedupKey: 'n2',
      ),
    );
    await tester.pumpWidget(
      harness(NotificationsScreen(db: db, did: me, embedded: true)),
    );
    await shoot(tester, 'd02_notifications');
  });

  testWidgets('E · me / settings', (tester) async {
    final db = freshDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      harness(
        SettingsHomeScreen(
          db: db,
          did: me,
          embedded: true,
          personalScreenStyle: ElixScreenStyle.paper,
          forumScreenStyle: ElixScreenStyle.ink,
        ),
      ),
    );
    await shoot(tester, 'e01_me_settings');
  });
}
