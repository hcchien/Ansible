import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home shell pages can be changed by horizontal swipe', (
    tester,
  ) async {
    await _pumpHomeShell(tester, coachmarkSeen: true);

    expect(find.byKey(const Key('board_swipe_page_view')), findsOneWidget);
    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paper);

    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);
  });

  testWidgets('board switcher exposes tap tooltips and first-run guidance', (
    tester,
  ) async {
    await _pumpHomeShell(tester);

    expect(find.byTooltip('個人版 · 你的 Note 和 Murmur'), findsOneWidget);
    expect(find.byTooltip('討論區 · 追蹤的人與板'), findsOneWidget);
    expect(find.text('也可以點上方名稱直接切換'), findsOneWidget);
  });

  testWidgets('board swiper renders the 3D book-flip stage', (tester) async {
    await _pumpHomeShell(tester, coachmarkSeen: true);

    expect(find.byKey(const Key('board_swipe_3d_stage')), findsOneWidget);
    expect(
      find.byKey(const Key('board_swipe_page_transform_feed')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('board_swipe_page_transform_circle')),
      findsOneWidget,
    );
  });

  testWidgets('screen styles are configured independently per main screen', (
    tester,
  ) async {
    await _pumpHomeShell(tester, coachmarkSeen: true);

    await tester.tap(find.byKey(const Key('screen_style_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screen_style_choice_vellum')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paperElev);

    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);

    await tester.tap(find.byKey(const Key('screen_style_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screen_style_choice_deep')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paperDeep);

    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paperElev);
  });
}

Future<void> _pumpHomeShell(
  WidgetTester tester, {
  bool coachmarkSeen = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (coachmarkSeen) 'elix_board_swipe_shown': true,
  });
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() => db.close());

  await tester.pumpWidget(
    MyApp(
      db: db,
      didManager: _EmptyDidManager(),
      didPlcManager: _ExistingDidPlcManager(),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(HomeShell), findsOneWidget);
}

Color? _screenStyleColor(WidgetTester tester, String screenName) {
  final box = tester.widget<AnimatedContainer>(
    find.byKey(Key('screen_style_scope_$screenName')),
  );
  final decoration = box.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

class _EmptyDidManager implements DidManager {
  @override
  Future<OwnedDid> generate() {
    throw UnimplementedError('Not used by this test.');
  }

  @override
  Future<OwnedDid?> load() async => null;

  @override
  Future<void> delete() async {}
}

class _ExistingDidPlcManager implements DidPlcManager {
  @override
  Future<DidPlcResult> createDid({
    required String handle,
    String pdsEndpoint = 'https://trisaura.io',
    String? signingKeyHex,
  }) {
    throw UnimplementedError('Not used by this test.');
  }

  @override
  Future<void> deleteDid() async {}

  @override
  Future<DidPlcResult?> loadDid() async => const DidPlcResult(
    did: 'did:plc:abcdefghijklmnop',
    genesisJson: '{"type":"plc_genesis"}',
    publicKeyHex: 'ab',
  );
}
