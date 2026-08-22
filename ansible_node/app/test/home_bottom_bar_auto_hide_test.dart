import 'package:ansible_node/screens/home/home_bottom_bar.dart';
import 'package:ansible_node/screens/home/home_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unread notifications use a filled bell and unread dot', (
    tester,
  ) async {
    Widget bar(int unreadCount) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: HomeBottomBar(
          selectedBoard: HomeBoard.timeline,
          onSelectBoard: (_) {},
          onCompose: () {},
          onNotifications: () {},
          onProfile: () {},
          unreadCount: unreadCount,
        ),
      ),
    );

    await tester.pumpWidget(bar(1));
    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsNothing);

    await tester.pumpWidget(bar(0));
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
