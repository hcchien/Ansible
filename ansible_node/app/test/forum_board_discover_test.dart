import 'package:ansible_node/screens/home/forum_board.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Board-subscription discoverability: the Forum board (討論區) must give the
// user a path to find + follow boards, especially when they have none. Widget
// tests assert zh-Hant copy because the test locale falls back to zh-Hant
// (uiCopy returns zh when no AppLocalizations is installed).
void main() {
  late AppDatabase db;
  late OpsDispatchService opsDispatchService;
  late AtProtoClient atProtoClient;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    opsDispatchService = OpsDispatchService(
      repository: DriftOpsQueueRepository(db),
    );
    atProtoClient = AtProtoClient();
  });

  tearDown(() async {
    await db.close();
  });

  Board board(String id, String title) {
    final now = DateTime.now().toUtc();
    return Board(
      id: id,
      slug: id,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<int> pumpForum(
    WidgetTester tester, {
    required List<Board> boards,
    required VoidCallback onDiscoverBoards,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumBoardView(
            compact: false,
            db: db,
            did: 'did:plc:test',
            loading: false,
            posts: const [],
            boards: boards,
            selectedBoardId: null,
            hasSelectedBoard: false,
            atProtoClient: atProtoClient,
            opsDispatchService: opsDispatchService,
            onFlushPendingOps: () async {},
            onCreateThread: () async {},
            onCreateBoard: () async {},
            onManageBoards: () async {},
            onDiscoverBoards: onDiscoverBoards,
            onOpenBoard: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    return 0;
  }

  testWidgets(
    'empty boards renders the find-boards CTA and invokes onDiscoverBoards',
    (tester) async {
      var discoverTaps = 0;
      await pumpForum(
        tester,
        boards: const [],
        onDiscoverBoards: () => discoverTaps++,
      );

      // Empty-state copy + primary CTA are present (zh-Hant).
      expect(find.text('還沒有訂閱任何討論區'), findsOneWidget);
      expect(find.text('尋找討論區'), findsOneWidget);
      expect(find.text("You haven't followed any boards yet"), findsNothing);

      await tester.tap(find.text('尋找討論區'));
      await tester.pump();

      expect(discoverTaps, 1);
    },
  );

  testWidgets(
    'with boards present the Discover action is still reachable and invokes '
    'onDiscoverBoards',
    (tester) async {
      var discoverTaps = 0;
      await pumpForum(
        tester,
        boards: [board('b1', '測試討論區')],
        onDiscoverBoards: () => discoverTaps++,
      );

      // No empty-state CTA when boards exist, but the always-available
      // "探索/Discover" action remains in the board-actions row.
      expect(find.text('尋找討論區'), findsNothing);
      expect(find.text('探索'), findsOneWidget);

      await tester.tap(find.text('探索'));
      await tester.pump();

      expect(discoverTaps, 1);
    },
  );
}
