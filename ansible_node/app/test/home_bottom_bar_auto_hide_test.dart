import 'package:ansible_node/screens/home/home_bottom_bar.dart';
import 'package:ansible_node/screens/home/home_types.dart';
import 'package:ansible_node/screens/home/compact_header.dart';
import 'package:ansible_node/theme/elix_screen_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'narrow phone exposes labelled Discover without losing other destinations',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var discoveries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: HomeBottomBar(
              selectedBoard: HomeBoard.timeline,
              onSelectBoard: (_) {},
              onCompose: () {},
              onProfile: () {},
              onDiscover: () => discoveries++,
            ),
          ),
        ),
      );
      expect(find.text('探索'), findsOneWidget);
      expect(find.text('時間軸'), findsOneWidget);
      expect(find.text('討論版'), findsOneWidget);
      expect(
        find.byKey(const Key('home_bottom_compose_button')),
        findsOneWidget,
      );
      expect(find.text('通知'), findsNothing);
      expect(find.text('我'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home_discover_tab')));
      expect(discoveries, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unread notifications use a filled bell and unread dot', (
    tester,
  ) async {
    var opened = 0;
    Widget bar(int unreadCount) => MaterialApp(
      home: Scaffold(
        body: HomeCompactHeader(
          colors: ElixScreenStyle.paper.data,
          onSearch: () {},
          onSync: () {},
          onNotifications: () => opened++,
          unreadCount: unreadCount,
        ),
      ),
    );

    await tester.pumpWidget(bar(1));
    await tester.tap(find.byKey(const Key('home_notifications_button')));
    expect(opened, 1);
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('home_notification_badge')))
          .isLabelVisible,
      isTrue,
    );
    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsNothing);

    await tester.pumpWidget(bar(0));
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('home_notification_badge')))
          .isLabelVisible,
      isFalse,
    );
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsNothing);
  });

  testWidgets('auto-hiding navigation releases space and restores itself', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AutoHidingHomeBottomBar(
                visible: visible,
                child: SizedBox(
                  height: 72,
                  child: Semantics(
                    button: true,
                    label: 'Navigation action',
                    child: ColoredBox(color: Colors.amber),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final reveal = find.byKey(const Key('home_bottom_navigation_reveal'));
    expect(tester.getSize(reveal).height, 72);

    update(() => visible = false);
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, 0);

    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).height, 72);
  });
}
