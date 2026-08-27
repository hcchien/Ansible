import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/services/app_sync_service.dart';
import 'package:ansible_node/services/network_status_service.dart';
import 'package:ansible_node/services/relay_discovery_client.dart';
import 'package:ansible_node/services/user_presence_verifier.dart';
import 'package:ansible_node/services/sync_authorization_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first run shows injected relay discovery starter board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          relayDiscoveryLoader: () async => _starterDiscovery(),
          autoSeedDefaultRelay: false,
          initialBoard: HomeBoard.personal,
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Relay online'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('compatible'), findsOneWidget);
    expect(find.byKey(const Key('wall_discovery_entry')), findsOneWidget);

    await _disposeWidgetTree(tester);
  });

  testWidgets('first run discovery is hidden when relay is configured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await _seedActiveRelay(db);
    var discoveryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          relayDiscoveryLoader: () async {
            discoveryCalls += 1;
            return _starterDiscovery();
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(discoveryCalls, 0);
    expect(find.text('Relay online'), findsNothing);
    expect(find.text('General'), findsNothing);
    expect(find.text('Start here'), findsNothing);

    await _disposeWidgetTree(tester);
  });

  testWidgets('first run discovery is hidden when hosted board is configured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await _seedHostedBoard(db);
    var discoveryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          relayDiscoveryLoader: () async {
            discoveryCalls += 1;
            return _starterDiscovery();
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(discoveryCalls, 0);
    expect(find.text('Relay online'), findsNothing);
    expect(find.text('General'), findsNothing);
    expect(find.text('Start here'), findsNothing);

    await _disposeWidgetTree(tester);
  });

  testWidgets('header sync button runs app-wide sync', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    var syncCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          syncRunner: () async {
            syncCalls += 1;
            return const AppSyncResult(
              pulledActivities: 0,
              publishSummary: PublicPublishSummary(
                publicItems: 1,
                enqueued: 1,
                published: 1,
              ),
            );
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byTooltip('同步'));
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(find.textContaining('同步完成'), findsOneWidget);

    await _disposeWidgetTree(tester);
  });

  testWidgets('denied device authentication prevents manual sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    var syncCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          userPresenceVerifier: _FakeUserPresenceVerifier(false),
          syncRunner: () async {
            syncCalls += 1;
            return const AppSyncResult(
              pulledActivities: 0,
              publishSummary: PublicPublishSummary(publicItems: 0),
            );
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byTooltip('同步'));
    await tester.pumpAndSettle();

    expect(syncCalls, 0);
    expect(find.textContaining('未上傳任何資料'), findsOneWidget);
    await _disposeWidgetTree(tester);
  });

  testWidgets(
    'manual sync reuses one short authorization until app backgrounding',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final verifier = _FakeUserPresenceVerifier(true);
      final authorization = SyncAuthorizationController();
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeShell(
            db: db,
            did: 'did:plc:alice',
            networkStatusMonitor: _FakeNetworkStatusMonitor(
              NetworkStatus.online,
            ),
            relayDiscoveryLoader: () async => _emptyDiscovery(),
            userPresenceVerifier: verifier,
            syncAuthorizationController: authorization,
            syncRunner: () async {
              syncCalls += 1;
              return const AppSyncResult(
                pulledActivities: 0,
                publishSummary: PublicPublishSummary(publicItems: 0),
              );
            },
          ),
        ),
      );
      for (var i = 0; i < 8; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.tap(find.byTooltip('同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('同步'));
      await tester.pumpAndSettle();

      expect(syncCalls, 2);
      expect(verifier.calls, 1);

      // iOS may emit `inactive` while its own Face ID sheet is visible. That
      // transient state must not invalidate the grant being established.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byTooltip('同步'));
      await tester.pumpAndSettle();

      expect(syncCalls, 3);
      expect(verifier.calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byTooltip('同步'));
      await tester.pumpAndSettle();

      expect(syncCalls, 4);
      expect(verifier.calls, 2);
      await _disposeWidgetTree(tester);
    },
  );

  testWidgets('compact header keeps network chrome out of focus navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final network = _FakeNetworkStatusMonitor(NetworkStatus.online);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: network,
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          autoSeedDefaultRelay: false,
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byTooltip('已連線 · WiFi'), findsNothing);
    expect(find.byKey(const Key('compact_home_sync_button')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('compact_home_sync_button'))).dx,
      lessThan(tester.getCenter(find.byTooltip('搜尋')).dx),
    );
    expect(find.byKey(const Key('board_switch_personal')), findsNothing);
    expect(find.byKey(const Key('board_switch_timeline')), findsOneWidget);
    expect(find.byKey(const Key('board_switch_forum')), findsOneWidget);
  });

  testWidgets('header sync prompts setup when no sync target is configured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final network = _FakeNetworkStatusMonitor(NetworkStatus.online);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: network,
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          autoSeedDefaultRelay: false,
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byTooltip('同步'));
    await tester.pumpAndSettle();

    expect(find.textContaining('請先設定 Elix Relay'), findsOneWidget);
    expect(find.textContaining('同步完成'), findsNothing);

    await _disposeWidgetTree(tester);
  });

  testWidgets('startup pull refresh runs when online with active relay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'elix-genesis-subscribed': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await _seedActiveRelay(db);
    final network = _FakeNetworkStatusMonitor(NetworkStatus.online);
    var pullCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: network,
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          defaultSubscriptionsDiscoveryLoader: () async => _emptyDiscovery(),
          pullRefreshRunner: () async {
            pullCalls += 1;
            return const RelayPullSummary(pulledActivities: 1);
          },
        ),
      ),
    );
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(pullCalls, 1);
  });

  testWidgets('startup creates board subscriptions before history pull', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await _seedActiveRelay(db);
    final network = _FakeNetworkStatusMonitor(NetworkStatus.online);
    var pullCalls = 0;
    var subscriptionsReadyAtPull = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: network,
          relayDiscoveryLoader: () async => _starterDiscovery(),
          defaultSubscriptionsDiscoveryLoader: () async => _starterDiscovery(),
          pullRefreshRunner: () async {
            pullCalls += 1;
            subscriptionsReadyAtPull = (await DriftHostedBoardRepository(
              db,
            ).listSubscriptions()).isNotEmpty;
            return const RelayPullSummary(pulledActivities: 1);
          },
        ),
      ),
    );
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(pullCalls, 1);
    expect(subscriptionsReadyAtPull, isTrue);

    await _disposeWidgetTree(tester);
  });

  testWidgets('startup syncs accepted user follows into local contacts', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final now = DateTime.utc(2026, 5, 15);
    final followRepo = DriftFollowRepository(db);
    await followRepo.upsertTarget(
      FollowTarget(
        targetId: 'target-bob',
        targetType: FollowTargetType.user,
        canonicalUri: 'https://relay.example/users/bob',
        displayName: 'Bob',
        handle: 'bob.elix.app',
        did: 'did:plc:bob',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await followRepo.upsertEdge(
      FollowEdge(
        followId: 'follow-bob',
        followerDid: 'did:plc:alice',
        targetId: 'target-bob',
        targetType: FollowTargetType.user,
        direction: FollowDirection.outbound,
        status: FollowStatus.accepted,
        visibility: FollowVisibility.localOnly,
        createdAt: now,
        updatedAt: now,
        acceptedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          autoSeedDefaultRelay: false,
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final contact = await DriftContactRepository(
      db,
    ).contactForDid('did:plc:bob');
    expect(contact!.label, 'Bob');
    expect(contact.handle, 'bob.elix.app');
  });

  testWidgets(
    'timeline groups many replies under one opening post with context',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'elix-genesis-subscribed': true,
        'elix-swipe-coachmark-seen': true,
      });
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 8, 27, 8);
      final boardRepo = DriftBoardRepository(db);
      final threadRepo = DriftThreadRepository(db);
      final postRepo = DriftPostRepository(db);
      final followRepo = DriftFollowRepository(db);

      await boardRepo.create(
        Board(
          id: 'board-context',
          slug: 'context',
          title: 'Context board',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await threadRepo.create(
        Thread(
          id: 'thread-context',
          boardId: 'board-context',
          title: 'Original thread title',
          authorId: 'did:plc:op',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await postRepo.create(
        Post(
          id: 'opening-post',
          threadId: 'thread-context',
          boardId: 'board-context',
          authorId: 'did:plc:op',
          content: 'Original context that every reply needs',
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
          signatureVerified: true,
        ),
      );
      for (var i = 1; i <= 4; i += 1) {
        final timestamp = now.add(Duration(minutes: i));
        await postRepo.create(
          Post(
            id: 'reply-$i',
            threadId: 'thread-context',
            boardId: 'board-context',
            authorId: 'did:plc:bob',
            content: 'Reply number $i',
            createdAt: timestamp,
            updatedAt: timestamp,
            lastEditAt: timestamp,
            signatureVerified: true,
          ),
        );
      }
      await followRepo.upsertTarget(
        FollowTarget(
          targetId: 'target-bob-context',
          targetType: FollowTargetType.user,
          canonicalUri: 'did:plc:bob',
          displayName: 'Bob',
          did: 'did:plc:bob',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await followRepo.upsertEdge(
        FollowEdge(
          followId: 'follow-bob-context',
          followerDid: 'did:plc:alice',
          targetId: 'target-bob-context',
          targetType: FollowTargetType.user,
          direction: FollowDirection.outbound,
          status: FollowStatus.accepted,
          visibility: FollowVisibility.localOnly,
          createdAt: now,
          updatedAt: now,
          acceptedAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeShell(
            db: db,
            did: 'did:plc:alice',
            networkStatusMonitor: _FakeNetworkStatusMonitor(
              NetworkStatus.online,
            ),
            relayDiscoveryLoader: () async => _emptyDiscovery(),
            autoSeedDefaultRelay: false,
            initialBoard: HomeBoard.timeline,
          ),
        ),
      );
      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final timeline = find.byKey(
        const Key('board_swipe_page_transform_timeline'),
      );
      expect(
        find.descendant(of: timeline, matching: find.byType(PostCard)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timeline,
          matching: find.text('Original context that every reply needs'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timeline,
          matching: find.byKey(const Key('thread_reply_preview_reply-4')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timeline,
          matching: find.byKey(const Key('thread_reply_preview_reply-1')),
        ),
        findsNothing,
        reason: 'A single thread card caps its inline reply previews at three.',
      );

      await _disposeWidgetTree(tester);
    },
  );

  testWidgets('foreground resume pull refresh runs when online', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await _seedActiveRelay(db);
    final network = _FakeNetworkStatusMonitor(NetworkStatus.online);
    var pullCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: network,
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          pullRefreshRunner: () async {
            pullCalls += 1;
            return const RelayPullSummary(pulledActivities: 1);
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(pullCalls, 2);
  });

  testWidgets('online transition pull refresh runs once with active relay', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await _seedActiveRelay(db);
    final network = _FakeNetworkStatusMonitor(NetworkStatus.offline);
    var pullCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          networkStatusMonitor: network,
          relayDiscoveryLoader: () async => _emptyDiscovery(),
          pullRefreshRunner: () async {
            pullCalls += 1;
            return const RelayPullSummary(pulledActivities: 1);
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(pullCalls, 0);

    network.setStatus(NetworkStatus.online);
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(pullCalls, 1);
  });
}

RelayDiscovery _starterDiscovery() {
  return const RelayDiscovery(
    version: 1,
    relay: RelayDiscoveryRelay(
      serverKind: 'elixRelay',
      origin: 'https://relay.example',
      capabilities: {'forum_host_discovery': true},
    ),
    announcements: [
      RelayAnnouncement(
        announcementId: 'relay-online',
        ownerKind: 'relay',
        title: 'Relay online',
        body: 'Discovery ready',
        severity: 'info',
      ),
    ],
    featuredForumHosts: [
      DiscoveredForumHost(
        forumHostId: 'host-general',
        displayName: 'Starter Forum Host',
        forumHostUrl: 'https://relay.example',
        constitutionCompliance: 'constitution_compliant',
      ),
    ],
    featuredBoards: [
      DiscoveredBoard(
        hostedBoardId: 'general',
        title: 'General',
        description: 'Start here',
        forumHostUrl: 'https://relay.example',
        canonicalBoardUri: 'https://relay.example/boards/general',
        constitutionCompliance: 'compatible',
      ),
    ],
  );
}

RelayDiscovery _emptyDiscovery() {
  return const RelayDiscovery(
    version: 1,
    relay: RelayDiscoveryRelay(
      serverKind: 'elixRelay',
      origin: 'https://relay.example',
      capabilities: {'forum_host_discovery': true},
    ),
    announcements: [],
    featuredForumHosts: [],
    featuredBoards: [],
  );
}

Future<void> _seedActiveRelay(AppDatabase db) async {
  await DriftRemoteNodeRepository(db).create(
    RemoteNode(
      id: 'relay',
      name: 'Local relay',
      url: 'http://127.0.0.1:4001',
      isActive: true,
      createdAt: DateTime.utc(2026, 5, 10),
      updatedAt: DateTime.utc(2026, 5, 10),
    ),
  );
}

Future<void> _seedHostedBoard(AppDatabase db) async {
  final now = DateTime.utc(2026, 5, 10);
  final hostedBoards = DriftHostedBoardRepository(db);
  await hostedBoards.upsertProjection(
    HostedBoardProjection(
      localBoardId: 'local-hosted-board',
      forumHostId: 'host-1',
      hostedBoardId: 'hosted-board-1',
      canonicalBoardUri: 'https://forum.example/boards/hosted-board-1',
      remoteSlug: 'hosted',
      localSlug: 'hosted',
      title: 'Hosted Board',
      description: 'Already configured hosted board',
      permissions: const {'read': true, 'write': true},
      createdAt: now,
      updatedAt: now,
    ),
  );
  await hostedBoards.upsertSubscription(
    BoardSubscription(
      subscriptionId: 'host-1_hosted-board-1',
      forumHostId: 'host-1',
      hostedBoardId: 'hosted-board-1',
      localBoardId: 'local-hosted-board',
      readEnabled: true,
      writeEnabled: true,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

class _FakeNetworkStatusMonitor extends ChangeNotifier
    implements NetworkStatusMonitor {
  _FakeNetworkStatusMonitor(this._status);

  NetworkStatus _status;

  void setStatus(NetworkStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  NetworkStatus get status => _status;

  @override
  bool get isOnline => _status == NetworkStatus.online;

  @override
  bool get isOffline => _status == NetworkStatus.offline;

  @override
  bool get isChecking => _status == NetworkStatus.checking;

  @override
  String get connectionType => 'WiFi';

  @override
  DateTime? get lastChecked => DateTime.utc(2026, 5, 10);

  @override
  List<ConnectivityResult> get connectivityResults => const [
    ConnectivityResult.wifi,
  ];

  @override
  Future<void> checkStatus() async {}

  @override
  Future<bool> isUrlReachable(String url) async => true;
}

class _FakeUserPresenceVerifier implements UserPresenceVerifier {
  _FakeUserPresenceVerifier(this.result);

  final bool result;
  int calls = 0;

  @override
  Future<bool> verify({required String reason}) async {
    calls += 1;
    return result;
  }
}

Future<void> _disposeWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}
