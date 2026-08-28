import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/screens/user_profile_screen.dart';
import 'package:ansible_node/services/handle_resolver.dart';
import 'package:ansible_node/widgets/follow_button.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

    FollowButton button() =>
        tester.widget<FollowButton>(find.byType(FollowButton));

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

  testWidgets('profile lists only public posts and de-duplicates discussions', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final now = DateTime.utc(2026, 8, 27);

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          db: db,
          followerDid: 'did:key:local',
          did: 'did:key:alice',
          displayName: 'Alice',
          publicPostsLoader: (_) async => [
            AppViewTimelineItem(
              entityType: 'thread',
              entityId: 'thread-1',
              authorDid: 'did:key:alice',
              boardId: 'board-1',
              threadId: 'thread-1',
              visibility: 'public',
              createdAt: now.subtract(const Duration(hours: 2)),
              payload: const {'boardId': 'board-1', 'title': '公開討論標題'},
            ),
            AppViewTimelineItem(
              entityType: 'post',
              entityId: 'post-1',
              authorDid: 'did:key:alice',
              boardId: 'board-1',
              threadId: 'thread-1',
              visibility: 'public',
              createdAt: now.subtract(const Duration(hours: 1)),
              payload: const {
                'boardId': 'board-1',
                'threadId': 'thread-1',
                'content': '公開討論內容',
              },
            ),
            AppViewTimelineItem(
              entityType: 'murmur',
              entityId: 'murmur-1',
              authorDid: 'did:key:alice',
              visibility: 'public',
              createdAt: now,
              payload: const {'body': '公開碎念'},
            ),
            AppViewTimelineItem(
              entityType: 'note',
              entityId: 'note-hidden',
              authorDid: 'did:key:alice',
              visibility: 'unlisted',
              createdAt: now,
              payload: const {'body': '不應列出的 unlisted 內容'},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('公開貼文'), findsOneWidget);
    expect(find.text('公開碎念'), findsOneWidget);
    expect(find.text('公開討論標題'), findsOneWidget);
    expect(find.text('公開討論內容'), findsOneWidget);
    expect(find.text('不應列出的 unlisted 內容'), findsNothing);
    expect(find.byKey(const Key('public_profile_post_post-1')), findsOneWidget);
    expect(find.byKey(const Key('public_profile_post_thread-1')), findsNothing);
  });

  testWidgets('own profile does not show a follow button', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          db: db,
          followerDid: 'did:key:alice',
          did: 'did:key:alice',
          displayName: 'Alice',
          publicPostsLoader: (_) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FollowButton), findsNothing);
    expect(find.text('目前沒有公開貼文'), findsOneWidget);
  });

  testWidgets('own profile refreshes once across the AppView projection window', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    var requests = 0;
    final handleResolver = HandleResolver(
      baseUrl: 'https://relay.example',
      client: MockClient((_) async => http.Response('', 404)),
    );
    final profileResolver = PublicProfileResolver(
      baseUrl: 'https://appview.example',
      handleResolver: handleResolver,
      client: MockClient((_) async {
        requests += 1;
        return http.Response(
          requests == 1
              ? '{"did":"did:key:alice","display_name":"Alice","public_credentials":[]}'
              : '{"did":"did:key:alice","display_name":"Alice","public_credentials":[{"credential_type":"AgeOver18Credential","issuer_did":"did:web:issuer.elix.cool","badge":"age_over_18","value":"true"}]}',
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          db: db,
          followerDid: 'did:key:alice',
          did: 'did:key:alice',
          resolver: handleResolver,
          profileResolver: profileResolver,
          publicPostsLoader: (_) async => const [],
          profileProjectionRefreshDelay: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('已滿 18 歲'), findsNothing);
    expect(requests, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('已滿 18 歲'), findsOneWidget);
    expect(requests, 2);
  });

  testWidgets('desktop profile adds a public-data context rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final handleResolver = HandleResolver(
      baseUrl: 'https://relay.example',
      client: MockClient((_) async => http.Response('', 404)),
    );
    final profileResolver = PublicProfileResolver(
      baseUrl: 'https://appview.example',
      handleResolver: handleResolver,
      client: MockClient(
        (_) async => http.Response(
          '{"did":"did:key:alice","display_name":"Alice","handle":"alice.elix.cool","bio":"Public words only","reputation_tier":"verified_human","public_credentials":[{"credential_type":"AgeOver18Credential","issuer_did":"did:web:issuer.elix.cool","badge":"age_over_18","value":"true","valid_until":"2027-08-27T00:00:00Z"}]}',
          200,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          db: db,
          followerDid: 'did:key:local',
          did: 'did:key:alice',
          resolver: handleResolver,
          profileResolver: profileResolver,
          publicPostsLoader: (_) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('@alice.elix.cool'), findsOneWidget);
    expect(find.text('Public words only'), findsOneWidget);
    expect(find.text('已滿 18 歲'), findsOneWidget);
    expect(find.textContaining('私鑰與原始憑證不會進入'), findsOneWidget);
  });

  testWidgets('mobile profile stays single-column at 375 points', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final handleResolver = HandleResolver(
      baseUrl: 'https://relay.example',
      client: MockClient((_) async => http.Response('', 404)),
    );
    final profileResolver = PublicProfileResolver(
      baseUrl: 'https://appview.example',
      handleResolver: handleResolver,
      client: MockClient(
        (_) async => http.Response(
          '{"did":"did:key:alice","display_name":"Alice","handle":"alice.elix.cool","bio":"Public words only"}',
          200,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          db: db,
          followerDid: 'did:key:local',
          did: 'did:key:alice',
          resolver: handleResolver,
          profileResolver: profileResolver,
          publicPostsLoader: (_) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('@alice.elix.cool'), findsOneWidget);
    expect(find.textContaining('私鑰與原始憑證不會進入'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
