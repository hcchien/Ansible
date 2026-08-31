import 'package:ansible_node/screens/deliberations_screen.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/theme/elix_screen_style.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paper deliberation stays light when the app theme is dark', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 29);
    final board = Board(
      id: 'board-1',
      slug: 'general',
      title: 'General',
      createdAt: now,
      updatedAt: now,
    );
    await DriftBoardRepository(db).create(board);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DeliberationsScreen(
          db: db,
          board: board,
          localDid: 'did:elix:local',
          screenStyle: ElixScreenStyle.paper,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final error = find.textContaining('board_not_hosted');
    expect(error, findsOneWidget);
    final themedContext = tester.element(error);
    expect(Theme.of(themedContext).brightness, Brightness.light);
    expect(
      Theme.of(themedContext).scaffoldBackgroundColor,
      AnsibleDesign.paper,
    );
  });

  testWidgets(
    'opinion map focuses one statement and renders truthful aggregate results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 8, 29);
      final projection = HostedBoardProjection(
        localBoardId: 'board-1',
        forumHostId: 'host-1',
        hostedBoardId: 'hosted-1',
        canonicalBoardUri: 'https://forum.example/boards/hosted-1',
        remoteSlug: 'general',
        localSlug: 'general',
        title: 'General',
        createdAt: now,
        updatedAt: now,
      );
      final host = RemoteNode(
        id: 'host-1',
        name: 'Forum',
        url: 'https://forum.example',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AnsibleDesign.theme(),
          home: DeliberationDetailScreen(
            db: db,
            projection: projection,
            host: host,
            localDid: 'did:elix:local',
            deliberationId: 'd-1',
            detailLoader: () async => {
              'deliberation': {
                'id': 'd-1',
                'title': '怎麼產生第二個有本土意識的政黨？',
                'prompt': '一起比較可能的路徑與代價。',
                'export_mode': 'aggregates_only',
                'statements': [
                  {'id': 's-1', 'text': '先團結既有力量，再扶持另一個本土政黨。'},
                  {'id': 's-2', 'text': '現在就要提供另一個值得信任的選擇。'},
                ],
                'report': {
                  'participant_count': 12,
                  'response_count': 20,
                  'statement_count': 2,
                  'cluster_status': 'aggregate_only',
                  'consensus': [
                    {'text': '現在就要提供另一個值得信任的選擇。', 'agree_ratio': 0.8},
                  ],
                  'disagreement': [
                    {
                      'text': '先團結既有力量，再扶持另一個本土政黨。',
                      'agree': 6,
                      'pass': 2,
                      'disagree': 4,
                    },
                  ],
                },
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deliberation_opinion_map')), findsOneWidget);
      expect(find.byKey(const Key('deliberation_progress')), findsOneWidget);
      expect(
        find.byKey(const Key('deliberation_statement_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('deliberation_stance_s-1_disagree')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('deliberation_stance_s-1_pass')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('deliberation_stance_s-1_agree')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('deliberation_results')), findsOneWidget);
      expect(find.textContaining('意見群組分析尚未啟用'), findsOneWidget);
      final consensus = tester.widget<Container>(
        find.byKey(const Key('deliberation_consensus_card')),
      );
      final decoration = consensus.decoration as BoxDecoration;
      expect(decoration.color, AnsibleDesign.highlight.withValues(alpha: 0.10));
      expect((decoration.border as Border).top.color, AnsibleDesign.highlight);
    },
  );

  testWidgets('desktop keeps participation and results in two columns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 29);

    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.theme(),
        home: DeliberationDetailScreen(
          db: db,
          projection: HostedBoardProjection(
            localBoardId: 'board-1',
            forumHostId: 'host-1',
            hostedBoardId: 'hosted-1',
            canonicalBoardUri: 'https://forum.example/boards/hosted-1',
            remoteSlug: 'general',
            localSlug: 'general',
            title: 'General',
            createdAt: now,
            updatedAt: now,
          ),
          host: RemoteNode(
            id: 'host-1',
            name: 'Forum',
            url: 'https://forum.example',
            createdAt: now,
            updatedAt: now,
          ),
          localDid: 'did:elix:local',
          deliberationId: 'd-1',
          detailLoader: () async => {
            'deliberation': {
              'id': 'd-1',
              'title': '共識討論',
              'prompt': '比較不同路徑。',
              'export_mode': 'aggregates_only',
              'statements': [
                {'id': 's-1', 'text': '這是一則待回應陳述。'},
              ],
              'report': {
                'participant_count': 3,
                'response_count': 3,
                'statement_count': 1,
                'cluster_status': 'aggregate_only',
              },
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final participation = find.byKey(const Key('deliberation_opinion_map'));
    final results = find.byKey(const Key('deliberation_results'));
    expect(participation, findsOneWidget);
    expect(results, findsOneWidget);
    expect(tester.getTopLeft(participation).dy, tester.getTopLeft(results).dy);
    expect(tester.getSize(results).width, 360);
  });
}
