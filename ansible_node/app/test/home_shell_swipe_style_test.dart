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

    // Three boards now: Personal │ Timeline │ Forum — two swipes to reach Forum.
    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);
  });

  testWidgets('settings icon does not overlap the Forum tab on phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeShell(tester, coachmarkSeen: true);

    final forumTab = tester.getRect(
      find.byKey(const Key('board_switch_forum')),
    );
    final settingsBtn = tester.getRect(
      find.byKey(const Key('settings_button')),
    );

    // The settings icon sits entirely to the right of the Forum (討論區) tab.
    expect(
      forumTab.right <= settingsBtn.left,
      isTrue,
      reason:
          'Forum tab (${forumTab.right}) overlaps settings icon (${settingsBtn.left})',
    );
  });

  testWidgets('board switcher exposes tap tooltips and first-run guidance', (
    tester,
  ) async {
    await _pumpHomeShell(tester);

    expect(find.byTooltip('Personal · your Notes and Murmurs'), findsOneWidget);
    expect(
      find.byTooltip('Timeline · posts from people you follow'),
      findsOneWidget,
    );
    expect(find.byTooltip('Forum · boards'), findsOneWidget);
    expect(find.text('This is your personal board.'), findsOneWidget);
    expect(
      find.text('Want to see others? Swipe left or tap Forum above.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'personal board uses plus compose and AI bridge, not prompt card',
    (tester) async {
      await _pumpHomeShell(tester, coachmarkSeen: true);

      expect(find.text('今天有什麼想記下的？'), findsNothing);
      expect(find.text('AI · BRIDGE'), findsOneWidget);
      expect(find.byKey(const Key('home_compose_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_compose_button')));
      await tester.pumpAndSettle();

      expect(find.text('Murmur'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
    },
  );

  testWidgets('board swiper renders the 3D book-flip stage', (tester) async {
    await _pumpHomeShell(tester, coachmarkSeen: true);

    expect(find.byKey(const Key('board_swipe_3d_stage')), findsOneWidget);
    expect(
      find.byKey(const Key('board_swipe_page_transform_feed')),
      findsOneWidget,
    );

    // One swipe lands on the Timeline board (middle of three).
    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('board_swipe_page_transform_timeline')),
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

    // Two swipes to cross Timeline and reach Forum.
    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(-340, 0),
    );
    await tester.pumpAndSettle();
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

    // Two swipes back across Timeline to the Personal board.
    await tester.drag(
      find.byKey(const Key('board_swipe_page_view')),
      const Offset(340, 0),
    );
    await tester.pumpAndSettle();
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

    expect(find.text('Interface & Language'), findsOneWidget);
    expect(find.text('Board Theme'), findsOneWidget);
    expect(find.text('Board Motion'), findsOneWidget);

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
    String pdsEndpoint = 'https://elix.cool',
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
