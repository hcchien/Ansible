import 'dart:convert';

import 'package:ansible_node/services/app_view_timeline_client.dart';
import 'package:ansible_node/services/community_notes_preferences.dart';
import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/widgets/community_notes_panel.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('renders public note and aggregate without private rater DID', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final appView = AppViewTimelineClient(
      baseUrl: 'https://appview.example',
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'target': {
                'entity_type': 'murmur',
                'entity_id': 'target-1',
                'op_id': 'target-op',
                'content_hash': List.filled(64, 'a').join(),
              },
              'notes': [
                {
                  'note_id': 'note-1',
                  'author_did': 'did:elix:author',
                  'body': '這裡有可查證的補充脈絡。',
                  'sources': [
                    {'url': 'https://example.com/source', 'title': '公開來源'},
                  ],
                  'target_entity_type': 'murmur',
                  'target_entity_id': 'target-1',
                  'target_op_id': 'target-op',
                  'target_content_hash': List.filled(64, 'a').join(),
                },
                {
                  'note_id': 'note-2',
                  'author_did': 'did:elix:other-author',
                  'body': '另一則仍有分歧的脈絡。',
                  'sources': [
                    {'url': 'https://example.com/other'},
                  ],
                  'target_entity_type': 'murmur',
                  'target_entity_id': 'target-1',
                  'target_op_id': 'target-op',
                  'target_content_hash': List.filled(64, 'a').join(),
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final forumHost = ForumHostClient(
      baseUrl: 'https://relay.example',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'statuses': [
              {
                'note_id': 'note-1',
                'status': 'helpful',
                'score': 0.95,
                'rating_count': 7,
                'scorer_id': 'elix_host_consensus',
                'scorer_version': 1,
                'top_tags': [
                  {'tag': 'good_sources', 'count': 5},
                ],
                'rater_did': 'did:elix:must-stay-private',
              },
              {
                'note_id': 'note-2',
                'status': 'disputed',
                'score': 0.5,
                'rating_count': 6,
              },
            ],
          }),
          200,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityNotesPanel(
            targetRef: 'target-1',
            localDid: 'did:elix:viewer',
            opsDispatchService: OpsDispatchService(
              repository: DriftOpsQueueRepository(db),
            ),
            onFlushPendingOps: () async {},
            appViewClient: appView,
            forumHostClient: forumHost,
            preferencesStore: const _VisiblePreferences(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('這裡有可查證的補充脈絡。'), findsOneWidget);
    expect(find.text('公開來源'), findsOneWidget);
    expect(find.text('社群認為有幫助'), findsOneWidget);
    expect(find.text('7 次評分'), findsOneWidget);
    expect(find.textContaining('elix_host_consensus v1'), findsOneWidget);
    expect(find.textContaining('good_sources'), findsOneWidget);
    expect(find.textContaining('did:elix:must-stay-private'), findsNothing);
    expect(find.textContaining('公眾只會看到聚合'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('community_note_note-1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('community_note_note-2'))).dy,
      ),
    );
  });

  testWidgets('stays hidden when the local preference is off', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityNotesPanel(
          targetRef: 'target-1',
          localDid: 'did:elix:viewer',
          opsDispatchService: OpsDispatchService(
            repository: DriftOpsQueueRepository(db),
          ),
          onFlushPendingOps: () async {},
          preferencesStore: const _HiddenPreferences(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community_notes_panel')), findsNothing);
  });

  testWidgets('AppView failure never blocks or replaces target content', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('原始內容仍可閱讀'),
              CommunityNotesPanel(
                targetRef: 'target-1',
                localDid: 'did:elix:viewer',
                opsDispatchService: OpsDispatchService(
                  repository: DriftOpsQueueRepository(db),
                ),
                onFlushPendingOps: () async {},
                appViewClient: AppViewTimelineClient(
                  baseUrl: 'https://appview.example',
                  client: MockClient((_) async => http.Response('{}', 503)),
                ),
                preferencesStore: const _VisiblePreferences(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('原始內容仍可閱讀'), findsOneWidget);
    expect(find.byKey(const Key('community_notes_panel')), findsNothing);
  });
}

class _VisiblePreferences implements CommunityNotesPreferencesStore {
  const _VisiblePreferences();

  @override
  Future<bool> showCommunityNotes() async => true;

  @override
  Future<void> setShowCommunityNotes(bool value) async {}
}

class _HiddenPreferences implements CommunityNotesPreferencesStore {
  const _HiddenPreferences();

  @override
  Future<bool> showCommunityNotes() async => false;

  @override
  Future<void> setShowCommunityNotes(bool value) async {}
}
