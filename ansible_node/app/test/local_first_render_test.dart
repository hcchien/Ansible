import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/config/app_environment.dart';
import 'package:ansible_node/screens/home/main_panel.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/screens/discover_screen.dart';
import 'package:ansible_node/screens/threads_list_screen.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:ansible_node/services/network_status_service.dart';
import 'package:ansible_node/services/relay_discovery_client.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previewDir = String.fromEnvironment('LOCAL_FIRST_PREVIEW_DIR');
final _now = DateTime.utc(2026, 9, 24);

void main() {
  late AppDatabase db;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ansible_node/embedding'),
          (_) async => List<double>.filled(512, 0),
        );
    SharedPreferences.setMockInitialValues({
      'elix-genesis-subscribed': true,
      'elix_board_swipe_shown': true,
    });
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  testWidgets(
    'local home renders while remote waits; refresh preserves rows and local edits',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DriftContentItemRepository(db);
      await repo.create(_content('cached', '本機已儲存的內容'));
      var pending = Completer<List<FollowTimelineItem>>();
      var calls = 0;
      final boundary = GlobalKey();
      if (_previewDir.isNotEmpty) {
        for (final entry in {
          'Noto Sans TC': 'assets/fonts/NotoSansTC-400.ttf',
          'Noto Serif TC': 'assets/fonts/NotoSerifTC-400.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
          'JetBrains Mono': 'assets/fonts/JetBrainsMono-Regular.ttf',
        }.entries) {
          await (FontLoader(
            entry.key,
          )..addFont(rootBundle.load(entry.value))).load();
        }
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AnsibleDesign.theme(),
            home: HomeShell(
              db: db,
              did: 'did:plc:alice',
              autoSeedDefaultRelay: false,
              networkStatusMonitor: _FakeNetworkStatusMonitor(
                NetworkStatus.online,
              ),
              relayDiscoveryLoader: () async => _emptyDiscovery(),
              timelineLoader: () {
                calls++;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await _pumpReads(tester);
      MainPanel panel() => tester.widget<MainPanel>(find.byType(MainPanel));
      expect(panel().loading, isFalse);
      expect(find.text('本機已儲存的內容'), findsOneWidget);
      expect(calls, 1);
      await _capture(tester, boundary, 'home-local-before-network');

      var refreshed = false;
      unawaited(panel().onRefresh().then((_) => refreshed = true));
      await _pumpReads(tester);
      expect(refreshed, isTrue, reason: 'Local refresh must not await HTTP.');
      expect(panel().loading, isFalse);
      expect(calls, 1, reason: 'Coalesce overlapping background requests.');
      expect(find.text('本機已儲存的內容'), findsOneWidget);

      await repo.update(_content('cached', '等待網路時，已在本機修改'));
      pending.complete([
        _remote(_content('cached', '舊的遠端文字')),
        _remote(_content('new', '剛取得的新內容')),
      ]);
      await _pumpReads(tester);
      expect(
        panel().followingPosts.where((p) => p.thread.id == 'cached'),
        hasLength(1),
      );
      expect(find.text('等待網路時，已在本機修改'), findsOneWidget);
      expect(find.text('舊的遠端文字'), findsNothing);
      expect(find.text('剛取得的新內容'), findsOneWidget);
      await _capture(tester, boundary, 'home-after-background-update');

      pending = Completer<List<FollowTimelineItem>>();
      unawaited(panel().onRefresh());
      await _pumpReads(tester);
      expect(find.text('剛取得的新內容'), findsOneWidget);
      pending.completeError(StateError('offline'));
      await _pumpReads(tester);
      expect(
        find.text('剛取得的新內容'),
        findsOneWidget,
        reason: 'A failed refresh must retain the last successful remote rows.',
      );

      // A cached remote copy cannot resurrect content made private locally.
      await repo.update(
        _content('cached', '私密內容', visibility: ContentVisibility.private),
      );
      pending = Completer<List<FollowTimelineItem>>();
      unawaited(panel().onRefresh());
      await _pumpReads(tester);
      expect(
        panel().followingPosts.any((p) => p.thread.id == 'cached'),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete([_remote(_content('late', 'late response'))]);
      await _pumpReads(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching Relay clears cached rows and rejects old responses', (
    tester,
  ) async {
    final originalRelay = AppEnvironment.socialRelayBaseUrl;
    addTearDown(() => AppEnvironment.socialRelayBaseUrl = originalRelay);
    final nodes = DriftRemoteNodeRepository(db);
    Future<void> selectRelay(String url) => nodes.create(
      RemoteNode(
        id: 'selected',
        name: 'Selected Relay',
        url: url,
        isActive: true,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await selectRelay('https://first.example');
    final oldResponse = Completer<List<FollowTimelineItem>>();
    final newResponse = Completer<List<FollowTimelineItem>>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          db: db,
          did: 'did:plc:alice',
          autoSeedDefaultRelay: false,
          networkStatusMonitor: _FakeNetworkStatusMonitor(NetworkStatus.online),
          timelineLoader: () {
            calls++;
            if (calls == 1) {
              return Future.value([_remote(_content('cached', 'First Relay'))]);
            }
            return calls == 2 ? oldResponse.future : newResponse.future;
          },
        ),
      ),
    );
    await _pumpReads(tester);
    MainPanel panel() => tester.widget<MainPanel>(find.byType(MainPanel));
    expect(panel().followingPosts, hasLength(1));
    unawaited(panel().onRefresh());
    await _pumpReads(tester);
    expect(calls, 2);
    await selectRelay('https://second.example');
    unawaited(panel().onRefresh());
    await _pumpReads(tester);
    expect(panel().followingPosts, isEmpty);
    oldResponse.complete([_remote(_content('late', 'Old Relay response'))]);
    await _pumpReads(tester);
    expect(calls, 3);
    expect(panel().followingPosts, isEmpty);
    newResponse.complete([_remote(_content('current', 'Current Relay'))]);
    await _pumpReads(tester);
    expect(panel().followingPosts.map((post) => post.thread.id), ['current']);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpReads(tester);
  });

  testWidgets(
    'empty local timeline waits for remote before claiming it is empty',
    (tester) async {
      final pending = Completer<List<FollowTimelineItem>>();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeShell(
            db: db,
            did: 'did:plc:alice',
            autoSeedDefaultRelay: false,
            networkStatusMonitor: _FakeNetworkStatusMonitor(
              NetworkStatus.online,
            ),
            relayDiscoveryLoader: () async => _emptyDiscovery(),
            timelineLoader: () => pending.future,
          ),
        ),
      );
      await _pumpReads(tester);
      expect(find.text('動態牆還沒有內容'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      pending.complete([]);
      await _pumpReads(tester);
      expect(find.text('動態牆還沒有內容'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [390.0, 834.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'local home renders at $width in ${brightness.name} while offline',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          SharedPreferences.setMockInitialValues({
            'elix-genesis-subscribed': true,
            'elix_board_swipe_shown': true,
            'elix-screen-style.feed': 'system',
          });
          await DriftContentItemRepository(
            db,
          ).create(_content('cached', '本機內容 離線也能閱讀'));
          var remoteCalls = 0;
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: brightness == Brightness.dark
                    ? AnsibleDesign.darkTheme()
                    : AnsibleDesign.theme(),
                home: HomeShell(
                  db: db,
                  did: 'did:plc:alice',
                  autoSeedDefaultRelay: false,
                  networkStatusMonitor: _FakeNetworkStatusMonitor(
                    NetworkStatus.offline,
                  ),
                  relayDiscoveryLoader: () async => _emptyDiscovery(),
                  timelineLoader: () async {
                    remoteCalls++;
                    return [];
                  },
                ),
              ),
            ),
          );
          await _pumpReads(tester);
          expect(find.text('本機內容 離線也能閱讀'), findsOneWidget);
          expect(remoteCalls, 0);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            boundary,
            'home-${width.toInt()}-${brightness.name}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpReads(tester);
        },
      );
    }
  }

  testWidgets('board local threads render without waiting for deliberations', (
    tester,
  ) async {
    final board = await _seedBoard(db);
    final pending = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadsListScreen(
          db: db,
          board: board,
          localDid: 'did:plc:alice',
          deliberationsLoader: (_) => pending.future,
        ),
      ),
    );
    await _pumpReads(tester);
    expect(find.text('可離線閱讀的討論'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.completeError(StateError('host unavailable'));
    await _pumpReads(tester);
    expect(find.text('可離線閱讀的討論'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'discovery shows local boards then online boards while people and posts wait',
    (tester) async {
      await _seedBoard(db);
      final boardResponse = Completer<http.Response>();
      final otherResponses = Completer<http.Response>();
      final client = DiscoveryClient(
        appViewBaseUrl: 'https://app.test',
        relayBaseUrl: 'https://relay.test',
        client: MockClient(
          (request) => request.url.path.contains('boards')
              ? boardResponse.future
              : otherResponses.future,
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoverScreen(
            db: db,
            localDid: 'did:plc:alice',
            client: client,
            startOnBoards: true,
          ),
        ),
      );
      await _pumpReads(tester);
      expect(find.text('本機看板'), findsOneWidget);
      boardResponse.complete(
        http.Response(
          jsonEncode({
            'boards': [
              {'hosted_board_id': 'online-board', 'title': '新的公開看板'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await _pumpReads(tester);
      expect(find.text('新的公開看板'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      otherResponses.completeError(StateError('appview unavailable'));
      await _pumpReads(tester);
      expect(find.text('新的公開看板'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpReads(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ContentItem _content(
  String id,
  String body, {
  ContentVisibility visibility = ContentVisibility.public,
}) => ContentItem(
  id: id,
  authorDid: 'did:plc:alice',
  mode: ContentMode.murmur,
  body: body,
  status: ContentStatus.active,
  visibility: visibility,
  localOnly: false,
  signatureVerified: true,
  createdAt: _now,
  updatedAt: _now,
);
FollowTimelineItem _remote(ContentItem content) => ContentTimelineItem(
  ContentFeedEntry(
    item: content,
    reasons: const {FollowFeedReason.followedUser},
  ),
);

Future<Board> _seedBoard(AppDatabase db) async {
  final board = Board(
    id: 'board',
    slug: 'board',
    title: '本機看板',
    createdAt: _now,
    updatedAt: _now,
  );
  await DriftBoardRepository(db).create(board);
  await DriftHostedBoardRepository(db).upsertProjection(
    HostedBoardProjection(
      localBoardId: board.id,
      forumHostId: 'host',
      hostedBoardId: 'remote-board',
      canonicalBoardUri: 'https://host.test/boards/remote-board',
      remoteSlug: 'remote-board',
      localSlug: board.slug,
      title: board.title,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await DriftHostedBoardRepository(db).upsertSubscription(
    BoardSubscription(
      subscriptionId: 'subscription',
      forumHostId: 'host',
      hostedBoardId: 'remote-board',
      localBoardId: board.id,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await DriftThreadRepository(db).create(
    Thread(
      id: 'thread',
      boardId: board.id,
      authorId: 'did:plc:alice',
      title: '可離線閱讀的討論',
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return board;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_previewDir.isEmpty) return;
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_previewDir).create(recursive: true);
    await File(
      '$_previewDir/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
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
