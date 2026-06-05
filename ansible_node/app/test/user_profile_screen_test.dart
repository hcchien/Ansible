import 'package:ansible_node/screens/user_profile_screen.dart';
import 'package:ansible_node/widgets/follow_button.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('follow then unfollow a user from the profile', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          db: db,
          followerDid: 'did:key:local',
          did: 'did:key:alice',
          displayName: 'Alice',
        ),
      ),
    );
    await tester.pumpAndSettle();

    FollowButton button() => tester.widget<FollowButton>(find.byType(FollowButton));

    // Initially not following.
    expect(button().status, FollowButtonStatus.notFollowing);

    // Follow.
    await tester.tap(find.byType(FollowButton));
    await tester.pumpAndSettle();
    expect(button().status, FollowButtonStatus.following);

    final followRepo = DriftFollowRepository(db);
    final following = await followRepo.listFollowing(
      'did:key:local',
      targetType: FollowTargetType.user,
    );
    expect(following.single.status, FollowStatus.accepted);

    // Unfollow.
    await tester.tap(find.byType(FollowButton));
    await tester.pumpAndSettle();
    expect(button().status, FollowButtonStatus.notFollowing);

    final after = await followRepo.listFollowing(
      'did:key:local',
      targetType: FollowTargetType.user,
    );
    expect(after, isEmpty); // cancelled edges are excluded from listFollowing
  });
}
