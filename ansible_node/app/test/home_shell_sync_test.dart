import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/services/app_sync_service.dart';
import 'package:ansible_node/services/network_status_service.dart';
import 'package:ansible_node/services/relay_discovery_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
          relayDiscoveryLoader: () async => _starterDiscovery(),
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Relay online'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Start here'), findsOneWidget);

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
    expect(find.textContaining('public publish 1/1 targets'), findsOneWidget);

    await _disposeWidgetTree(tester);
  });

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
        ),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byTooltip('已連線 · WiFi'), findsNothing);
    expect(find.byKey(const Key('board_switch_personal')), findsOneWidget);
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

    expect(pullCalls, 1);
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
        home: HomeShell(db: db, did: 'did:plc:alice'),
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
        constitutionCompliance: 'unknown',
      ),
    ],
    featuredBoards: [
      DiscoveredBoard(
        hostedBoardId: 'general',
        title: 'General',
        description: 'Start here',
        forumHostUrl: 'https://relay.example',
        canonicalBoardUri: 'https://relay.example/boards/general',
        constitutionCompliance: 'unknown',
      ),
    ],
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

Future<void> _disposeWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}
