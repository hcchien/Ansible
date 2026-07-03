import 'package:ansible_node/l10n/user_facing_error.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_node/services/posting_gate.dart';
import 'package:ansible_node/widgets/board_gate_badge.dart';
import 'package:ansible_store/ansible_store.dart' hide Board;
import 'package:ansible_store/ansible_store.dart' as store show Board;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests assert zh-Hant copy because the test locale falls back to
// zh-Hant (see existing screen tests).
void main() {
  const gatedPolicy = {'min_post_tier': PostingGate.verifiedHumanTier};

  group('PostingGate ordering', () {
    test('ungated board accepts every tier', () {
      expect(PostingGate.satisfies(PostingGate.basicTier, null), isTrue);
      expect(PostingGate.satisfies('unknown_tier', null), isTrue);
    });

    test('verified_human gate rejects basic and accepts verified_human', () {
      expect(
        PostingGate.satisfies(
          PostingGate.basicTier,
          PostingGate.verifiedHumanTier,
        ),
        isFalse,
      );
      expect(
        PostingGate.satisfies(
          PostingGate.verifiedHumanTier,
          PostingGate.verifiedHumanTier,
        ),
        isTrue,
      );
    });

    test('unknown tiers fail closed on both sides', () {
      expect(
        PostingGate.satisfies('future_tier', PostingGate.verifiedHumanTier),
        isFalse,
      );
      expect(
        PostingGate.satisfies(PostingGate.verifiedHumanTier, 'future_gate'),
        isFalse,
      );
    });
  });

  testWidgets('board gate badge renders the verified-only chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BoardGateBadge())),
    );

    expect(find.text('真人版'), findsOneWidget);
  });

  group('ThreadsListScreen posting gate', () {
    const localDid = 'did:plc:gate-test-user';

    Future<store.Board> seedBoard(
      AppDatabase db, {
      Map<String, Object?> postingPolicy = const {},
    }) async {
      final now = DateTime.now().toUtc();
      final board = store.Board(
        id: 'board-gated',
        slug: 'gated',
        title: 'Gated Board',
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
          remoteSlug: 'gated',
          localSlug: 'gated',
          title: 'Gated Board',
          postingPolicy: postingPolicy,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return board;
    }

    Future<void> pumpThreads(
      WidgetTester tester,
      AppDatabase db,
      store.Board board,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThreadsListScreen(db: db, board: board, localDid: localDid),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('basic-tier user sees the notice and a disabled composer', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedBoard(db, postingPolicy: gatedPolicy);
      // No reputation row → tierFor falls back to basic.

      await pumpThreads(tester, db, board);

      expect(find.text('此看板僅限通過真人驗證的成員發文'), findsOneWidget);
      // No reachable issuer in tests → the CTA shows the honest interim
      // state (UX review P1: never a wizard that cannot finish).
      expect(find.text('真人驗證即將開放'), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
    });

    testWidgets('verified-human user posts normally on a gated board', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedBoard(db, postingPolicy: gatedPolicy);
      await DriftDidReputationRepository(
        db,
      ).put(localDid, PostingGate.verifiedHumanTier);

      await pumpThreads(tester, db, board);

      expect(find.text('此看板僅限通過真人驗證的成員發文'), findsNothing);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNotNull);
    });

    testWidgets('ungated board shows no notice for basic-tier users', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final board = await seedBoard(db);

      await pumpThreads(tester, db, board);

      expect(find.text('此看板僅限通過真人驗證的成員發文'), findsNothing);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNotNull);
    });
  });

  testWidgets('relay posting_requires_tier 403 maps to friendly copy', (
    tester,
  ) async {
    late String message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            message = userFacingError(
              context,
              const ForumHostException(
                statusCode: 403,
                error: 'posting_requires_tier',
                body: {
                  'error': 'posting_requires_tier',
                  'required_tier': 'verified_human',
                  'current_tier': 'basic',
                },
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(message, contains('真人驗證'));
    expect(message, isNot(contains('posting_requires_tier')));
    expect(message, isNot(contains('403')));
  });
}
