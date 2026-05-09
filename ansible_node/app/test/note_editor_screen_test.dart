import 'package:ansible_node/screens/note_editor_screen.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('note editor publishes composed title and body', (tester) async {
    final atProtoClient = _FakeAtProtoClient();
    final signer = _FakeLexiconSigner();

    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.theme(),
        home: NoteEditorScreen(
          authorDid: 'did:plc:alice',
          boardId: 'board-1',
          threadId: 'thread-1',
          threadTitle: 'Field notes',
          atProtoClient: atProtoClient,
          lexiconSigner: signer,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('note_editor_title_field')),
      '末日松茸採集',
    );
    await tester.enterText(
      find.byKey(const Key('note_editor_body_field')),
      '林下不是空的，只是用看不見的方式生長著。',
    );
    await tester.tap(find.byKey(const Key('note_editor_done_button')));
    await tester.pumpAndSettle();

    expect(signer.record?['text'], '末日松茸採集\n\n林下不是空的，只是用看不見的方式生長著。');
    expect(signer.record?['threadId'], 'thread-1');
    expect(atProtoClient.request?.repo, 'did:plc:alice');
    expect(atProtoClient.request?.collection, LexiconPost.type);
    expect(atProtoClient.request?.commitSig, _FakeLexiconSigner.signature);
  });

  testWidgets('note editor rejects an empty draft', (tester) async {
    final atProtoClient = _FakeAtProtoClient();
    final signer = _FakeLexiconSigner();

    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.theme(),
        home: NoteEditorScreen(
          authorDid: 'did:plc:alice',
          boardId: 'board-1',
          threadId: '',
          threadTitle: '',
          atProtoClient: atProtoClient,
          lexiconSigner: signer,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('note_editor_done_button')));
    await tester.pumpAndSettle();

    expect(find.text('內容不得為空'), findsOneWidget);
    expect(signer.record, isNull);
    expect(atProtoClient.request, isNull);
  });
}

class _FakeLexiconSigner implements LexiconSigner {
  static const signature =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

  Map<String, dynamic>? record;

  @override
  Future<SignedLexiconRecord> sign(
    Map<String, dynamic> record, {
    required String authorDid,
  }) async {
    this.record = record;
    return SignedLexiconRecord(
      record: record,
      cid: 'bafy-test',
      commitSigHex: signature,
      authorDid: authorDid,
    );
  }
}

class _FakeAtProtoClient extends AtProtoClient {
  _FakeAtProtoClient() : super(baseUrl: 'http://unused.local');

  CreateRecordRequest? request;

  @override
  Future<CreateRecordResult> createRecord(CreateRecordRequest req) async {
    request = req;
    return const CreateRecordResult(
      uri: 'at://did:plc:alice/post/1',
      cid: 'bafy-test',
    );
  }
}
