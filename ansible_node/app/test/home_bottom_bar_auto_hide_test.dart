import 'package:ansible_node/screens/home/home_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
