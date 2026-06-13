import 'dart:convert';

import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_node/widgets/report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
}
