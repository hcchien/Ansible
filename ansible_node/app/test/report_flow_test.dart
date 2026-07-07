import 'dart:convert';

import 'package:ansible_node/screens/posts_view_screen.dart';
import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_node/widgets/report_dialog.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records the submitted intent instead of hitting the network; throws
/// [error] first when set (failure-path tests).
class _RecordingForumHostClient extends ForumHostClient {
  _RecordingForumHostClient() : super(baseUrl: 'https://host.example');

  ReportContentIntent? submitted;
  Object? error;

  @override
  Future<ReportSubmission> submitReport(ReportContentIntent intent) async {
    submitted = intent;
    final failure = error;
    if (failure != null) throw failure;
    return const ReportSubmission(
      duplicate: false,
      report: {'id': 'r1', 'status': 'open'},
    );
  }
}

void main() {
  group('ReportContentIntent canonical payload', () {
    test('keys are sorted to match the relay canonical JSON', () {
      final payload = ReportContentIntent.canonicalPayload(
        intentId: 'intent-1',
        authorDid: 'did:plc:reporter',
        targetForumHost: 'https://relay.example',
        targetKind: 'post',
        targetRef: 'post-1',
        boardId: 'hosted-1',
        reasonCode: 'spam',
        note: 'note',
        createdAt: DateTime.utc(2026, 6, 13),
        expiresAt: DateTime.utc(2026, 6, 13, 0, 5),
      );

      expect(payload.keys.toList(), [
        'action',
        'author_did',
        'created_at',
        'expires_at',
        'intent_id',
        'report',
        'target_forum_host',
        'type',
        'version',
      ]);
      final report = payload['report'] as Map<String, Object?>;
      expect(report.keys.toList(), [
        'board_id',
        'note',
        'reason_code',
        'target_kind',
        'target_ref',
      ]);
      expect(payload['action'], 'report_content');
      expect(payload['type'], 'io.trisaura.forum.reportContent');
    });

    test('empty note is omitted from the payload', () {
      final payload = ReportContentIntent.canonicalPayload(
        intentId: 'intent-1',
        authorDid: 'did:plc:reporter',
        targetForumHost: 'https://relay.example',
        targetKind: 'thread',
        targetRef: 'thread-1',
        boardId: 'hosted-1',
        reasonCode: 'spam',
        createdAt: DateTime.utc(2026, 6, 13),
        expiresAt: DateTime.utc(2026, 6, 13, 0, 5),
      );

      final report = payload['report'] as Map<String, Object?>;
      expect(report.containsKey('note'), isFalse);
    });
  });

  group('ForumHostClient.submitReport', () {
    ReportContentIntent intent() => ReportContentIntent(
      intentId: 'intent-1',
      authorDid: 'did:plc:reporter',
      targetForumHost: 'https://relay.example',
      signature: 'deadbeef',
      targetKind: 'post',
      targetRef: 'post-1',
      boardId: 'hosted-1',
      reasonCode: 'spam',
      createdAt: DateTime.utc(2026, 6, 13),
      expiresAt: DateTime.utc(2026, 6, 13, 0, 5),
    );

    test('201 returns a non-duplicate submission', () async {
      late Map<String, dynamic> sent;
      final client = ForumHostClient(
        baseUrl: 'https://relay.example',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/forum-host/reports');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'report': {'id': 'r1', 'status': 'open'},
            }),
            201,
          );
        }),
      );

      final submission = await client.submitReport(intent());

      expect(submission.duplicate, isFalse);
      expect(submission.report['id'], 'r1');
      expect(sent['signature'], 'deadbeef');
      expect(sent['report'], {
        'board_id': 'hosted-1',
        'reason_code': 'spam',
        'target_kind': 'post',
        'target_ref': 'post-1',
      });
    });

    test('200 marks the submission as a duplicate', () async {
      final client = ForumHostClient(
        baseUrl: 'https://relay.example',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'report': {'id': 'r1', 'status': 'open'},
            }),
            200,
          ),
        ),
      );

      final submission = await client.submitReport(intent());

      expect(submission.duplicate, isTrue);
    });

    test('429 surfaces as a ForumHostException with rate_limited', () async {
      final client = ForumHostClient(
        baseUrl: 'https://relay.example',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'error': 'rate_limited'}), 429),
        ),
      );

      await expectLater(
        client.submitReport(intent()),
        throwsA(
          isA<ForumHostException>().having(
            (e) => e.error,
            'error',
            'rate_limited',
          ),
        ),
      );
    });
  });

  group('report dialog', () {
    Future<Future<ReportDraft?>> openDialog(WidgetTester tester) async {
      late Future<ReportDraft?> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = showReportDialog(context),
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

    testWidgets('other without a note is rejected inline', (tester) async {
      final result = await openDialog(tester);

      await tester.tap(find.byKey(const Key('report_reason_other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('選擇「其他」時請填寫說明'), findsOneWidget);

      // Filling the note lets the draft through.
      await tester.enterText(
        find.byKey(const Key('report_note_field')),
        '冒充板務發公告',
      );
      await tester.tap(find.byKey(const Key('report_submit_button')));
      await tester.pumpAndSettle();

      final draft = await result;
      expect(draft?.reasonCode, 'other');
      expect(draft?.note, '冒充板務發公告');
    });

    testWidgets('default reason submits without a note', (tester) async {
      final result = await openDialog(tester);

      await tester.tap(find.byKey(const Key('report_submit_button')));
      await tester.pumpAndSettle();

      final draft = await result;
      expect(draft?.reasonCode, 'spam');
      expect(draft?.note, isNull);
    });
  });

  // Full report rail through the thread view: overflow/app-bar action →
  // reason dialog → signed intent handed to the (fake) Forum Host client.
  // Widget copy assertions are zh-Hant (test locale fallback).
  group('report submission from the thread view', () {
    const localDid = 'did:plc:local-user';
    const otherDid = 'did:plc:someone-else';
    final now = DateTime.utc(2026, 7, 7);

    late AppDatabase db;
    late Thread thread;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await DriftBoardRepository(db).create(
        Board(
          id: 'board-1',
          slug: 'general',
          title: 'General',
          createdAt: now,
          updatedAt: now,
        ),
      );
      thread = Thread(
        id: 'thread-1',
        boardId: 'board-1',
        title: 'A thread',
        authorId: otherDid,
        createdAt: now,
        updatedAt: now,
      );
      await DriftThreadRepository(db).create(thread);
      await DriftPostRepository(db).create(
        Post(
          id: 'post-1',
          threadId: 'thread-1',
          boardId: 'board-1',
          authorId: otherDid,
          content: 'questionable content',
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
        ),
      );
      await DriftHostedBoardRepository(db).upsertProjection(
        HostedBoardProjection(
          localBoardId: 'board-1',
          forumHostId: 'host-1',
          hostedBoardId: 'hosted-1',
          canonicalBoardUri: 'https://host.example/boards/hosted-1',
          remoteSlug: 'general',
          localSlug: 'general',
          title: 'General',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await DriftRemoteNodeRepository(db).create(
        RemoteNode(
          id: 'host-1',
          name: 'Host',
          url: 'https://host.example',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    tearDown(() => db.close());

    Future<void> pumpThreadView(
      WidgetTester tester,
      _RecordingForumHostClient client,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PostsViewScreen(
            db: db,
            thread: thread,
            authorDid: localDid,
            reportClientFactory: (_) => client,
            reportPayloadSigner: (_) async => 'facadefeed',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('post report submits a signed reason-coded intent', (
      tester,
    ) async {
      final client = _RecordingForumHostClient();
      await pumpThreadView(tester, client);

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('檢舉'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report_reason_harassment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report_submit_button')));
      await tester.pumpAndSettle();

      final intent = client.submitted;
      expect(intent, isNotNull);
      expect(intent!.targetKind, 'post');
      expect(intent.targetRef, 'post-1');
      expect(intent.boardId, 'hosted-1');
      expect(intent.reasonCode, 'harassment');
      expect(intent.authorDid, localDid);
      expect(intent.targetForumHost, 'https://host.example');
      expect(intent.signature, 'facadefeed');
      // Confirmation snackbar.
      expect(find.text('已送出檢舉，將由板務依板規處理'), findsOneWidget);
    });

    testWidgets('thread report targets the thread itself', (tester) async {
      final client = _RecordingForumHostClient();
      await pumpThreadView(tester, client);

      await tester.tap(find.byKey(const Key('report_thread_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report_submit_button')));
      await tester.pumpAndSettle();

      final intent = client.submitted;
      expect(intent, isNotNull);
      expect(intent!.targetKind, 'thread');
      expect(intent.targetRef, 'thread-1');
      expect(intent.reasonCode, 'spam');
    });

    testWidgets('submission failure surfaces localized user-facing copy', (
      tester,
    ) async {
      final client = _RecordingForumHostClient()
        ..error = const ForumHostException(
          statusCode: 429,
          body: {},
          error: 'rate_limited',
        );
      await pumpThreadView(tester, client);

      await tester.tap(find.byKey(const Key('report_thread_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('操作太頻繁，請稍後再試。'), findsOneWidget);
      expect(find.text('已送出檢舉，將由板務依板規處理'), findsNothing);
    });
  });
}
