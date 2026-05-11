import 'package:ansible_node/screens/credential_admin_screen.dart';
import 'package:ansible_node/screens/note_editor_screen.dart';
import 'package:ansible_node/screens/profile_screen.dart';
import 'package:ansible_node/screens/search_screen.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('search screen renders empty states instead of sample results', (
    tester,
  ) async {
    await _pumpTall(tester, const SearchScreen());

    expect(find.text('目前沒有筆記'), findsOneWidget);
    expect(find.text('目前沒有碎念'), findsOneWidget);
    expect(find.text('目前沒有討論串'), findsOneWidget);
    _expectNoLegacyMockText();
  });

  testWidgets('profile screen renders unset state instead of sample profile', (
    tester,
  ) async {
    await _pumpTall(tester, const ProfileScreen());

    expect(find.text('尚未設定公開身分'), findsOneWidget);
    expect(find.text('目前沒有公開發布'), findsOneWidget);
    _expectNoLegacyMockText();
  });

  testWidgets('credential admin renders empty grants and audit log', (
    tester,
  ) async {
    await _pumpTall(tester, const CredentialAdminScreen());

    expect(find.text('目前沒有授權紀錄'), findsOneWidget);
    expect(find.text('目前沒有存取紀錄'), findsOneWidget);
    _expectNoLegacyMockText();
  });

  testWidgets('note editor does not render sample note or murmur data', (
    tester,
  ) async {
    await _pumpTall(
      tester,
      NoteEditorScreen(
        authorDid: 'did:plc:alice',
        boardId: 'board-1',
        threadId: 'thread-1',
        threadTitle: '',
        atProtoClient: _FakeAtProtoClient(),
        lexiconSigner: _FakeLexiconSigner(),
      ),
    );

    expect(find.text('筆記標題'), findsOneWidget);
    expect(find.text('寫下筆記內容'), findsOneWidget);
    expect(find.text('繼續寫下去……'), findsOneWidget);
    expect(find.text('編入 · DRAW IN'), findsNothing);
    _expectNoLegacyMockText();
  });

  testWidgets('settings screen does not show sample identity/status data', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await _pumpTall(
      tester,
      SettingsHomeScreen(db: db, did: 'did:plc:abcdefghijklmnop'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('本機身分'), findsOneWidget);
    expect(find.text('Tris'), findsNothing);
    expect(find.text('3 台裝置 · 點對點'), findsNothing);
    expect(find.text('松茸 · 大'), findsNothing);
  });
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(theme: AnsibleDesign.theme(), home: child),
  );
  await tester.pump();
}

void _expectNoLegacyMockText() {
  for (final text in _legacyMockTexts) {
    expect(find.text(text), findsNothing, reason: 'legacy mock text: $text');
  }
  for (final text in _legacyMockFragments) {
    expect(
      find.textContaining(text),
      findsNothing,
      reason: 'legacy mock fragment: $text',
    );
  }
}

const _legacyMockTexts = [
  '週四讀書會',
  '廢墟中的協作',
  '關於 Le Guin 的 Ansible',
  '我們在「廢墟」裡到底在尋找什麼？',
  '荒涼感作為一種介面語言',
  '末日松茸採集',
  '松茸喜歡的是被擾動過、卻沒被毀掉的林子。',
  'MURMUR · 04.27 14:36',
  'Tris ↔ kr.',
  '同居寫作組',
  '公開討論',
  'under-the-canopy',
];

const _legacyMockFragments = [
  '林下',
  'Anna Tsing',
  'patches',
  'mushroom at the end of the world',
  '讀書會',
  'kr.',
  'iPad',
  '路過的人',
];

class _FakeLexiconSigner implements LexiconSigner {
  @override
  Future<SignedLexiconRecord> sign(
    Map<String, dynamic> record, {
    required String authorDid,
  }) async {
    return SignedLexiconRecord(
      record: record,
      cid: 'bafy-test',
      commitSigHex: 'deadbeef',
      authorDid: authorDid,
    );
  }
}

class _FakeAtProtoClient extends AtProtoClient {
  _FakeAtProtoClient() : super(baseUrl: 'http://unused.local');

  @override
  Future<CreateRecordResult> createRecord(CreateRecordRequest req) async {
    return const CreateRecordResult(
      uri: 'at://did:plc:alice/post/1',
      cid: 'bafy-test',
    );
  }
}
