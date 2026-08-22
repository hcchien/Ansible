import 'package:ansible_node/screens/home/board_swipe_header.dart';
import 'package:ansible_node/screens/home/home_types.dart';
import 'package:ansible_node/theme/elix_screen_style.dart';
import 'package:ansible_node/widgets/feed_filter_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide header uses a filled bell while notifications are unread', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardSwipeHeader(
            pageController: controller,
            selectedBoard: HomeBoard.timeline,
            onTapBoard: (_) {},
            personalStyle: ElixScreenStyle.paper,
            timelineStyle: ElixScreenStyle.paper,
            forumStyle: ElixScreenStyle.paper,
            personalFilter: PersonalFilter.all,
            onPersonalFilterChanged: (_) {},
            feedFilter: FeedFilter.all,
            onFeedFilterChanged: (_) {},
            forumPostCount: 0,
            onOpenNotifications: () {},
            notificationUnreadCount: 2,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    expect(find.byKey(const Key('notifications_unread_badge')), findsOneWidget);
  });
}
