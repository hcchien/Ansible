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
    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.darkPaper);

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
    expect(find.text('這裡是你的個人版。'), findsOneWidget);
    expect(find.text('想看別人？往左滑，或是點上面的「討論區」。'), findsOneWidget);
  });

  testWidgets(
    'personal board uses plus compose and AI bridge, not prompt card',
    (tester) async {
      await _pumpHomeShell(tester, coachmarkSeen: true);

      expect(find.text('今天有什麼想記下的？'), findsNothing);
      expect(find.text('AI · 橫向橋'), findsOneWidget);
      expect(find.byKey(const Key('home_compose_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_compose_button')));
      await tester.pumpAndSettle();

      expect(find.text('碎念'), findsOneWidget);
      expect(find.text('筆記'), findsOneWidget);
    },
  );

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
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeShell(tester, coachmarkSeen: true);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.tap(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_done_button')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paper);

    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings_style_choice_forum_ink')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_style_choice_forum_ink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_done_button')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.darkPaper);

    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paper);
  });

  testWidgets('interface preferences live in settings on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeShell(tester, coachmarkSeen: true);

    expect(find.byKey(const Key('screen_style_button')), findsNothing);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    expect(find.text('介面與語言'), findsOneWidget);
    expect(find.text('每版的光'), findsOneWidget);
    expect(find.text('換版的動態'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.tap(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_motion_slide')));
    await tester.pumpAndSettle();

    expect(find.text('Paper / Paper'), findsOneWidget);
    expect(find.text('Slide'), findsWidgets);
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
