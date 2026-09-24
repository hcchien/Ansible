import 'package:ansible_node/widgets/animated_feed_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    List<(String, String)> items, {
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: AnimatedFeedList<(String, String)>(
            items: items,
            itemId: (item) => item.$1,
            itemRevision: (item) => item.$2,
            itemBuilder: (_, item) =>
                SizedBox(height: 120, child: Text(item.$2)),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'updated rows animate; unchanged rows retain their element and opacity',
    (tester) async {
      await show(tester, [('a', 'old'), ('b', 'unchanged')]);
      final stable = tester.element(find.text('unchanged'));
      await show(tester, [('a', 'updated'), ('b', 'unchanged')]);
      expect(tester.element(find.text('unchanged')), same(stable));
      double opacityFor(String id) => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(ValueKey(id)),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      expect(opacityFor('a'), lessThan(1));
      expect(opacityFor('b'), 1);
      await tester.pumpAndSettle();
      expect(opacityFor('a'), 1);
    },
  );

  testWidgets(
    'prepended rows wait while reading; deletion still applies immediately',
    (tester) async {
      final items = [for (var i = 0; i < 20; i++) ('$i', 'row $i')];
      await show(tester, items);
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('row 5'));
      await show(tester, [('new', 'new row'), ...items]);
      expect(tester.getTopLeft(find.text('row 5')), before);
      expect(find.byKey(const Key('feed_show_updates')), findsOneWidget);
      expect(find.text('new row'), findsNothing);
      await tester.tap(find.byKey(const Key('feed_show_updates')));
      await tester.pumpAndSettle();
      expect(find.text('new row'), findsOneWidget);
      expect(find.byKey(const Key('feed_show_updates')), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      await show(tester, items.where((item) => item.$1 != '5').toList());
      expect(find.text('row 5'), findsNothing);
      expect(find.byKey(const Key('feed_show_updates')), findsNothing);
    },
  );

  testWidgets('reduced motion updates immediately without animation', (
    tester,
  ) async {
    await show(tester, [('a', 'old')], reducedMotion: true);
    await show(tester, [('new', 'new row'), ('a', 'new')], reducedMotion: true);
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .every((o) => o.opacity == 1),
      isTrue,
    );
  });
}
