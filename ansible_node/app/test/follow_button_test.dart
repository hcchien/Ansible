import 'package:ansible_node/widgets/follow_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('follow button displays status label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowButton(
            status: FollowButtonStatus.notFollowing,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Follow'), findsOneWidget);
  });
}
