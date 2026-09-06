import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/canonical_identity_store.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/screens/discover_screen.dart';
import 'package:ansible_node/screens/notifications_screen.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accepted_terms_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Discover is a phone destination with navigation still available',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHomeShell(tester, coachmarkSeen: true);
      await tester.tap(find.byKey(const Key('home_discover_tab')));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoverScreen), findsOneWidget);
      expect(find.byKey(const Key('settings_button')), findsOneWidget);
      expect(find.byKey(const Key('board_switch_timeline')), findsOneWidget);
      await tester.tap(find.byKey(const Key('board_switch_timeline')));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoverScreen), findsNothing);
      expect(find.byKey(const Key('board_swipe_page_view')), findsOneWidget);
    },
  );

  testWidgets(
    'boards and a fixed notification bell remain reachable across phone destinations',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHomeShell(tester, coachmarkSeen: true);
      final bell = find.byKey(const Key('home_notifications_button'));
      final originalPosition = tester.getRect(bell);
      for (final destination in [
        'board_switch_forum',
        'home_discover_tab',
        'settings_button',
        'board_switch_timeline',
      ]) {
        await tester.tap(find.byKey(Key(destination)));
        await tester.pumpAndSettle();
        expect(tester.getRect(bell), originalPosition);
        expect(find.byKey(const Key('board_switch_forum')), findsOneWidget);
        if (destination == 'board_switch_forum') {
          expect(find.byType(DiscoverScreen), findsNothing);
          expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);
        }
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(tester.getRect(bell), originalPosition);
      }
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getRect(bell), originalPosition);
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home shell pages can be changed by horizontal swipe', (
    tester,
  ) async {
    await _pumpHomeShell(tester, coachmarkSeen: true);

    expect(find.byKey(const Key('board_swipe_page_view')), findsOneWidget);
    // Feed now defaults to Paper (white) to match the Threads-style design.
    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paper);

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

  testWidgets('settings icon does not overlap Discover on phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeShell(tester, coachmarkSeen: true);

    final forumTab = tester.getRect(find.byKey(const Key('home_discover_tab')));
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

  testWidgets('compact compose tab matches the flat handoff treatment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeShell(tester, coachmarkSeen: true);

    final container = tester.widget<Container>(
      find.byKey(const Key('home_bottom_compose_button')),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, AnsibleDesign.accent);
    expect(decoration.boxShadow, isNull);

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('home_bottom_compose_button')),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(icon.color, Colors.white);
  });

  testWidgets('vertical content scroll hides and restores compact navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeShell(tester, coachmarkSeen: true);
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    final reveal = find.byKey(const Key('home_bottom_navigation_reveal'));
    expect(tester.getSize(reveal).height, greaterThan(0));

    final settingsScroll = find.byType(Scrollable).first;
    await tester.drag(settingsScroll, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, 0);

    await tester.drag(settingsScroll, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, greaterThan(0));
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

    // 我 (settings) and the boards are sibling bottom-nav destinations now.
    // Personal is reached from the in-settings 個人版 entry; forum from its
    // nav cell. (The bottom nav carries only 時間軸 + 討論區.)
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_style_choice_personal_paper')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.pumpAndSettle();
    // Scroll the settings list back to top so the (lazily-built) 個人版 entry
    // is mounted, then tap it to return to the personal board.
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_open_personal_board')),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_open_personal_board')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'feed'), AnsibleDesign.paper);

    // The settings scroll hides the compact navigation. Return toward the top
    // before using the Forum tab, as a user would.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_discover_tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover_tab_boards')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover_open_subscriptions')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.paper);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_style_choice_forum_ink')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_style_choice_forum_ink')));
    await tester.pumpAndSettle();
    // Returning toward the top reveals the auto-hidden navigation.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_discover_tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover_tab_boards')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover_open_subscriptions')));
    await tester.pumpAndSettle();

    expect(_screenStyleColor(tester, 'circle'), AnsibleDesign.darkPaper);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    // Scroll the settings list back to top so the (lazily-built) 個人版 entry
    // is mounted, then tap it to return to the personal board.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_open_personal_board')));
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

    // The settings list builds lazily; bring the interface section into view.
    await tester.scrollUntilVisible(
      find.text('Interface & Language'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Interface & Language'), findsOneWidget);
    expect(find.text('Board Theme'), findsOneWidget);
    expect(find.text('Board Motion'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_style_choice_personal_paper')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('settings_style_choice_personal_paper')),
    );
    await tester.pumpAndSettle();
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
      termsAcceptanceStore: const AcceptedTermsStore(),
      db: db,
      didManager: _EmptyDidManager(),
      didPlcManager: _ExistingDidPlcManager(),
      canonicalIdentityStore: InMemoryCanonicalIdentityStore(),
      // These cases exercise the personal board; land there explicitly now that
      // the app defaults to the Timeline.
      initialBoard: HomeBoard.personal,
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
  Future<void> deleteDid() async {}

  @override
  Future<DidPlcResult?> loadDid() async => const DidPlcResult(
    did: 'did:plc:abcdefghijklmnop',
    genesisJson: '{"type":"plc_genesis"}',
    publicKeyHex: 'ab',
  );
}
