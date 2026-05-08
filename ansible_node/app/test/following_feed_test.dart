import 'package:ansible_node/widgets/feed_filter_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('feed filter tabs report following selection', (tester) async {
    FeedFilter? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedFilterTabs(
            selected: FeedFilter.all,
            onChanged: (filter) => selected = filter,
          ),
        ),
      ),
    );

    await tester.tap(find.text('圈內'));
    await tester.pumpAndSettle();

    expect(selected, FeedFilter.following);
  });
}
