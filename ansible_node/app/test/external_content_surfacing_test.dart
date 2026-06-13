import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/services/app_view_timeline_client.dart';
import 'package:ansible_node/services/external_content_preferences_controller.dart';
import 'package:ansible_store/ansible_store.dart' hide Board;
import 'package:ansible_store/ansible_store.dart' as store show Board;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests assert zh-Hant copy because the test locale falls back to
// zh-Hant (see existing screen tests).
void main() {
  const externalInclusivePolicy = {'external_inclusion': true};

  AppViewExternalPage samplePage() => AppViewExternalPage(
    items: const [
      AppViewExternalItem(
        opId: 'op-ext-1',
        boardId: 'hosted-1',
        content: '哈囉 from the fediverse',
        externalActorUri: 'https://g0v.social/users/alice',
        externalInstance: 'g0v.social',
        complianceLevel: 'compatible',
      ),
    ],
    hasMore: false,
  );

  Future<store.Board> seedBoard(
    AppDatabase db, {
    Map<String, Object?> postingPolicy = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final board = store.Board(
      id: 'board-ext',
      slug: 'ext',
      title: 'External Board',
      createdAt: now,
      updatedAt: now,
    );
    await DriftBoardRepository(db).create(board);
    await DriftHostedBoardRepository(db).upsertProjection(
      HostedBoardProjection(
        localBoardId: board.id,
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        canonicalBoardUri: 'https://relay.example/boards/hosted-1',
        remoteSlug: 'ext',
        localSlug: 'ext',
        title: 'External Board',
        postingPolicy: postingPolicy,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return board;
  }

  Future<void> pumpBoard(
    WidgetTester tester,
    AppDatabase db,
    store.Board board, {
    required bool optIn,
    required VoidCallback onFetchCalled,
    AppViewExternalPage? page,
  }) async {
    final prefs = ExternalContentPreferencesController(
      store: InMemoryExternalContentPreferencesStore(showExternal: optIn),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadsListScreen(
          db: db,
          board: board,
          externalContentPreferences: prefs,
          externalFetcher: (boardId) async {
            onFetchCalled();
            return page ?? samplePage();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('ThreadsListScreen external content gating', () {
    testWidgets(
      'board NOT external-inclusive renders no section and makes no fetch',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => db.close());
        final board = await seedBoard(db); // no external_inclusion
        var fetched = false;

        await pumpBoard(
          tester,
          db,
          board,
          optIn: true,
          onFetchCalled: () => fetched = true,
        );

        expect(fetched, isFalse);
        expect(find.byKey(const Key('external_content_section')), findsNothing);
        expect(find.text('哈囉 from the fediverse'), findsNothing);
      },
    );

    testWidgets(
      'external-inclusive board but user opt-in OFF makes no fetch',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => db.close());
        final board = await seedBoard(
          db,
          postingPolicy: externalInclusivePolicy,
        );
        var fetched = false;

        await pumpBoard(
          tester,
          db,
          board,
          optIn: false,
          onFetchCalled: () => fetched = true,
        );

        expect(fetched, isFalse);
        expect(find.byKey(const Key('external_content_section')), findsNothing);
        expect(find.text('哈囉 from the fediverse'), findsNothing);
      },
    );

    testWidgets(
      'external-inclusive board AND opt-in ON renders the labeled section '
      'with origin and compliance badge',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => db.close());
        final board = await seedBoard(
          db,
          postingPolicy: externalInclusivePolicy,
        );
        var fetched = false;

        await pumpBoard(
          tester,
          db,
          board,
          optIn: true,
          onFetchCalled: () => fetched = true,
        );

        expect(fetched, isTrue);
        expect(
          find.byKey(const Key('external_content_section')),
          findsOneWidget,
        );
        expect(find.textContaining('站外內容'), findsWidgets);
        // Content + origin (instance + actor handle).
        expect(find.text('哈囉 from the fediverse'), findsOneWidget);
        expect(find.text('@alice@g0v.social'), findsOneWidget);
        // Compliance badge (compatible).
        expect(
          find.byKey(const Key('external_compliance_op-ext-1')),
          findsOneWidget,
        );
        expect(find.text('相容'), findsOneWidget);
      },
    );

    testWidgets('unknown compliance renders the UNKNOWN badge', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedBoard(
        db,
        postingPolicy: externalInclusivePolicy,
      );

      await pumpBoard(
        tester,
        db,
        board,
        optIn: true,
        onFetchCalled: () {},
        page: AppViewExternalPage(
          items: const [
            AppViewExternalItem(
              opId: 'op-ext-2',
              boardId: 'hosted-1',
              content: 'unassessed source',
              externalActorUri: 'https://mstdn.example/users/bob',
              externalInstance: 'mstdn.example',
              complianceLevel: 'unknown',
            ),
          ],
        ),
      );

      expect(find.text('未評估'), findsOneWidget);
    });
  });

  group('ExternalContentPreferencesController', () {
    test('defaults to OFF when never set', () async {
      final controller = ExternalContentPreferencesController(
        store: InMemoryExternalContentPreferencesStore(),
      );
      await controller.load();
      expect(controller.showExternal, isFalse);
    });

    test('persists the opt-in through the store', () async {
      final backing = InMemoryExternalContentPreferencesStore();
      final controller = ExternalContentPreferencesController(store: backing);
      await controller.load();

      await controller.setShowExternal(true);
      expect(controller.showExternal, isTrue);

      // A fresh controller over the same store reads the persisted value.
      final reloaded = ExternalContentPreferencesController(store: backing);
      await reloaded.load();
      expect(reloaded.showExternal, isTrue);
    });
  });
}
