import 'package:ansible_node/screens/thread_composer_screen.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/services/forum_publication_service.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the wiring call instead of writing publication targets.
class _RecordingPublicationService extends ForumPublicationService {
  _RecordingPublicationService(HostedBoardRepository hostedBoards)
    : super(hostedBoards: hostedBoards);

  String? localDraftId;
  String? primaryLocalBoardId;
  List<String>? crossPostTargetIds;

  @override
  Future<ForumPublicationResult?> createThreadForLocalBoard({
    required String localDraftId,
    required String primaryLocalBoardId,
    List<String> crossPostTargetIds = const [],
  }) async {
    this.localDraftId = localDraftId;
    this.primaryLocalBoardId = primaryLocalBoardId;
    this.crossPostTargetIds = crossPostTargetIds;
    return ForumPublicationResult(accepted: 1 + crossPostTargetIds.length);
  }
}

// Widget copy assertions are zh-Hant (test locale fallback).
void main() {
  const localDid = 'did:plc:local-user';
  final now = DateTime.utc(2026, 7, 7);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Board board(String id, String title) =>
      Board(id: id, slug: id, title: title, createdAt: now, updatedAt: now);

  Future<Board> seedBoard(String id, String title) async {
    final created = board(id, title);
    await DriftBoardRepository(db).create(created);
    return created;
  }

  Future<void> seedProjection(
    String boardId, {
    Map<String, Object?> postingPolicy = const {},
  }) {
    return DriftHostedBoardRepository(db).upsertProjection(
      HostedBoardProjection(
        localBoardId: boardId,
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-$boardId',
        canonicalBoardUri: 'https://host.example/boards/hosted-$boardId',
        remoteSlug: boardId,
        localSlug: boardId,
        title: boardId,
        postingPolicy: postingPolicy,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> seedSubscription(
    String subscriptionId,
    String boardId, {
    bool writeEnabled = true,
  }) {
    return DriftHostedBoardRepository(db).upsertSubscription(
      BoardSubscription(
        subscriptionId: subscriptionId,
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-$boardId',
        localBoardId: boardId,
        readEnabled: true,
        writeEnabled: writeEnabled,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Pushes the composer from a harness button so the popped result can be
  /// captured (the composer's contract is the map it pops).
  Future<Future<Map<String, Object?>?>> openComposer(
    WidgetTester tester, {
    required List<Board> boards,
    String? initialBoardId,
  }) async {
    late Future<Map<String, Object?>?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = Navigator.of(context).push<Map<String, Object?>>(
                  MaterialPageRoute(
                    builder: (_) => ThreadComposerScreen(
                      boards: boards,
                      initialBoardId: initialBoardId,
                      authorDid: localDid,
                      db: db,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  group('composer posting-gate pre-check', () {
    testWidgets('a gated board keeps a local draft and defers publication', (
      tester,
    ) async {
      final gated = await seedBoard('board-1', '真人版');
      await seedProjection(
        'board-1',
        postingPolicy: const {'min_post_tier': 'verified_human'},
      );

      final result = await openComposer(tester, boards: [gated]);

      expect(
        find.byKey(const Key('composer_posting_gate_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('未符合此看板的發文資格'), findsOneWidget);
      final done = tester.widget<FilledButton>(
        find.byKey(const Key('thread_composer_done_button')),
      );
      expect(done.onPressed, isNotNull);

      await tester.enterText(
        find.byKey(const Key('thread_composer_title_field')),
        '離線草稿',
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_body_field')),
        '取得資格後再同步',
      );
      await tester.tap(find.byKey(const Key('thread_composer_done_button')));
      await tester.pumpAndSettle();

      final popped = await result;
      expect(popped?['publicationDeferred'], isTrue);
      expect(popped?['crossPostTargetIds'], isEmpty);
    });

    testWidgets('a read-only subscription also defers publication', (
      tester,
    ) async {
      final readOnly = await seedBoard('board-1', '唯讀版');
      await seedProjection('board-1');
      await seedSubscription('sub-1', 'board-1', writeEnabled: false);

      final result = await openComposer(tester, boards: [readOnly]);

      expect(
        find.byKey(const Key('composer_posting_gate_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('目前只有閱讀權限'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('thread_composer_title_field')),
        '本機內容',
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_body_field')),
        '不因 relay 規則而遺失',
      );
      await tester.tap(find.byKey(const Key('thread_composer_done_button')));
      await tester.pumpAndSettle();

      expect((await result)?['publicationDeferred'], isTrue);
    });

    testWidgets('a verified user clears the gate', (tester) async {
      final gated = await seedBoard('board-1', '真人版');
      await seedProjection(
        'board-1',
        postingPolicy: const {'min_post_tier': 'verified_human'},
      );
      await DriftDidReputationRepository(db).put(localDid, 'verified_human');

      await openComposer(tester, boards: [gated]);

      expect(
        find.byKey(const Key('composer_posting_gate_banner')),
        findsNothing,
      );
      final done = tester.widget<FilledButton>(
        find.byKey(const Key('thread_composer_done_button')),
      );
      expect(done.onPressed, isNotNull);
    });

    testWidgets('an ungated board shows no banner and allows submit', (
      tester,
    ) async {
      final open = await seedBoard('board-1', 'General');
      await seedProjection('board-1');

      await openComposer(tester, boards: [open]);

      expect(
        find.byKey(const Key('composer_posting_gate_banner')),
        findsNothing,
      );
      final done = tester.widget<FilledButton>(
        find.byKey(const Key('thread_composer_done_button')),
      );
      expect(done.onPressed, isNotNull);
    });
  });

  testWidgets('title ink stays legible when the app uses its dark theme', (
    tester,
  ) async {
    final open = await seedBoard('board-1', 'General');
    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.darkTheme(),
        home: ThreadComposerScreen(
          boards: [open],
          initialBoardId: open.id,
          authorDid: localDid,
          db: db,
        ),
      ),
    );

    final title = tester.widget<TextField>(
      find.byKey(const Key('thread_composer_title_field')),
    );
    final decoration = title.decoration!;
    expect(decoration.filled, isFalse);
    expect(title.style?.color, AnsibleDesign.ink);
  });

  group('composer cross-post selector', () {
    testWidgets(
      'offers only other writable boards the user clears the gate for',
      (tester) async {
        final primary = await seedBoard('board-1', 'General');
        await seedBoard('board-2', 'News');
        await seedBoard('board-3', '真人版');
        await seedBoard('board-4', 'ReadOnly');
        await seedProjection('board-1');
        await seedProjection('board-2');
        await seedProjection(
          'board-3',
          postingPolicy: const {'min_post_tier': 'verified_human'},
        );
        await seedProjection('board-4');
        await seedSubscription('sub-1', 'board-1');
        await seedSubscription('sub-2', 'board-2');
        await seedSubscription('sub-3', 'board-3');
        await seedSubscription('sub-4', 'board-4', writeEnabled: false);

        final result = await openComposer(tester, boards: [primary]);

        expect(find.text('同時發佈到…'), findsOneWidget);
        // The primary board itself is excluded.
        expect(find.byKey(const Key('cross_post_target_sub-1')), findsNothing);
        // Writable + gate cleared: offered.
        expect(
          find.byKey(const Key('cross_post_target_sub-2')),
          findsOneWidget,
        );
        // Gated board the basic-tier user cannot post to: filtered out.
        expect(find.byKey(const Key('cross_post_target_sub-3')), findsNothing);
        // Read-only subscription: filtered out.
        expect(find.byKey(const Key('cross_post_target_sub-4')), findsNothing);

        await tester.tap(find.byKey(const Key('cross_post_target_sub-2')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('thread_composer_title_field')),
          '標題',
        );
        await tester.enterText(
          find.byKey(const Key('thread_composer_body_field')),
          '內文',
        );
        await tester.tap(find.byKey(const Key('thread_composer_done_button')));
        await tester.pumpAndSettle();

        final popped = await result;
        expect(popped?['boardId'], 'board-1');
        expect(popped?['title'], '標題');
        expect(popped?['content'], '內文');
        expect(popped?['crossPostTargetIds'], ['sub-2']);
      },
    );

    testWidgets('hides the selector when there is nothing to cross-post to', (
      tester,
    ) async {
      final primary = await seedBoard('board-1', 'General');
      await seedProjection('board-1');
      await seedSubscription('sub-1', 'board-1');

      await openComposer(tester, boards: [primary]);

      expect(find.text('同時發佈到…'), findsNothing);
    });
  });

  group('threads list composer wiring', () {
    testWidgets('selected cross-post ids flow to the publication service', (
      tester,
    ) async {
      final primary = await seedBoard('board-1', 'General');
      await seedBoard('board-2', 'News');
      await seedProjection('board-1');
      await seedProjection('board-2');
      await seedSubscription('sub-1', 'board-1');
      await seedSubscription('sub-2', 'board-2');
      final service = _RecordingPublicationService(
        DriftHostedBoardRepository(db),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ThreadsListScreen(
            db: db,
            board: primary,
            localDid: localDid,
            forumPublicationService: service,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('board_create_discussion_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('thread_composer_title_field')),
        '標題',
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_body_field')),
        '內文',
      );
      await tester.tap(find.byKey(const Key('cross_post_target_sub-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread_composer_done_button')));
      await tester.pumpAndSettle();

      expect(service.primaryLocalBoardId, 'board-1');
      expect(service.crossPostTargetIds, ['sub-2']);
      expect(service.localDraftId, isNotEmpty);
    });

    testWidgets('poll uses a dedicated editor with editable options', (
      tester,
    ) async {
      final primary = await seedBoard('board-1', 'General');
      await seedProjection('board-1');
      late Future<Map<String, Object?>?> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                result = Navigator.of(context).push<Map<String, Object?>>(
                  MaterialPageRoute(
                    builder: (_) => ThreadComposerScreen(
                      boards: [primary],
                      initialBoardId: primary.id,
                      authorDid: localDid,
                      db: db,
                      type: ThreadComposerType.poll,
                    ),
                  ),
                );
              },
              child: const Text('open poll'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open poll'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread_composer_poll_editor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thread_composer_poll_toggle')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_title_field')),
        '下季主題？',
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_body_field')),
        '請選擇。',
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_poll_option_0')),
        'AI',
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_poll_option_1')),
        '氣候',
      );
      final addOption = find.byKey(
        const Key('thread_composer_add_poll_option'),
      );
      await tester.ensureVisible(addOption);
      await tester.tap(addOption);
      await tester.pump();
      expect(
        find.byKey(const Key('thread_composer_poll_option_2')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('thread_composer_poll_option_2')),
        '生技',
      );
      await tester.tap(
        find.byKey(const Key('thread_composer_remove_poll_option_2')),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('thread_composer_poll_option_2')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('thread_composer_done_button')));
      await tester.pumpAndSettle();
      final poll = (await result)?['poll'] as Map<String, Object?>;
      expect(poll['options'], [
        {'id': 'option-1', 'label': 'AI'},
        {'id': 'option-2', 'label': '氣候'},
      ]);
      expect(poll['closes_at'], isA<String>());
    });
  });
}
