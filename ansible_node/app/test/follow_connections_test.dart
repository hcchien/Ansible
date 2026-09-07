import 'package:ansible_node/screens/follow_connections_screen.dart';
import 'package:ansible_node/services/follow_connections.dart';
import 'package:ansible_node/widgets/follow_connections_links.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = 'did:elix:owner';
Future<void> seed(AppDatabase db) async {
  final repo = DriftFollowRepository(db);
  final now = DateTime.utc(2026, 9, 7);
  for (final id in [
    'owner',
    'alice',
    'bob',
    'carol',
    'cancelled',
    'deleted',
    'board',
    'dave',
  ]) {
    await repo.upsertTarget(
      FollowTarget(
        targetId: id,
        targetType: id == 'board'
            ? FollowTargetType.board
            : FollowTargetType.user,
        canonicalUri: 'did:elix:$id',
        did: 'did:elix:$id',
        displayName: id,
        handle: '$id.elix.cool',
        isDeleted: id == 'deleted',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  Future<void> edge(
    String id,
    String target,
    FollowStatus status, {
    bool inbound = false,
    bool local = false,
    String follower = owner,
  }) => repo.upsertEdge(
    FollowEdge(
      followId: id,
      followerDid: follower,
      targetId: target,
      targetType: target == 'board'
          ? FollowTargetType.board
          : FollowTargetType.user,
      direction: inbound ? FollowDirection.inbound : FollowDirection.outbound,
      status: status,
      visibility: local
          ? FollowVisibility.localOnly
          : FollowVisibility.federated,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await edge('local-alice', 'alice', FollowStatus.accepted, local: true);
  await edge('pending-bob', 'bob', FollowStatus.pending);
  await edge('cancelled', 'cancelled', FollowStatus.cancelled);
  await edge('deleted', 'deleted', FollowStatus.accepted);
  await edge('board', 'board', FollowStatus.accepted);
  await edge(
    'someone-else',
    'dave',
    FollowStatus.accepted,
    follower: 'did:elix:another',
  );
  await edge(
    'carol-follows',
    'owner',
    FollowStatus.accepted,
    inbound: true,
    follower: 'did:elix:carol',
  );
  await edge(
    'dave-requests',
    'owner',
    FollowStatus.pending,
    inbound: true,
    follower: 'did:elix:dave',
  );
  await edge(
    'rejected',
    'owner',
    FollowStatus.rejected,
    inbound: true,
    follower: 'did:elix:bob',
  );
}

void main() {
  test(
    'own list preserves local-only and pending while excluding boards, deleted and inactive edges',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      final result = await loadFollowConnections(db, owner);
      expect(result.following.map((p) => p.name), ['alice', 'bob']);
      expect(result.followers.map((p) => p.name), ['carol', 'dave']);
      expect(result.followingCount, 1);
      expect(result.followerCount, 1);
      expect(result.following.first.localOnly, isTrue);
      expect(result.following.last.pending, isTrue);
    },
  );
  testWidgets(
    'own profile links open correct list with pending separated and searchable',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FollowConnectionsLinks(db: db, did: owner),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 追蹤中'), findsOneWidget);
      expect(find.text('1 追蹤者'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open_followers')));
      await tester.pumpAndSettle();
      expect(find.text('carol'), findsOneWidget);
      expect(find.text('等待你核准 1'), findsOneWidget);
      expect(find.text('dave'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('connections_search')),
        'carol.elix',
      );
      await tester.pump();
      expect(find.text('carol'), findsOneWidget);
      expect(find.text('dave'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('connections_search')),
        'absent',
      );
      await tester.pump();
      expect(find.text('沒有符合的使用者'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('connections_search')), '');
      await tester.tap(find.text('追蹤中 1'));
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('只在此裝置追蹤'), findsOneWidget);
      expect(find.text('等待對方核准 1'), findsOneWidget);
    },
  );
  testWidgets('320px empty list and account change show no old relationships', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    await tester.pumpWidget(
      MaterialApp(
        home: FollowConnectionsScreen(db: db, did: owner),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: FollowConnectionsScreen(db: db, did: 'did:elix:empty'),
      ),
    );
    await tester.pump();
    expect(find.text('alice'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('目前沒有追蹤任何人'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
