import 'dart:convert';

import 'package:ansible_node/screens/discover_screen.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  DiscoveryClient client() => DiscoveryClient(
    appViewBaseUrl: '',
    relayBaseUrl: 'https://relay.test',
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'boards': [
            {'hosted_board_id': 'general', 'title': 'General'},
            {'hosted_board_id': 'new-board', 'title': 'New Board'},
          ],
        }),
        200,
      ),
    ),
  );

  testWidgets('embedded discovery remains readable on a narrow dark phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.darkTheme(),
        home: Scaffold(
          body: DiscoverScreen(
            embedded: true,
            db: db,
            localDid: 'did:plc:test',
            client: client(),
            startOnBoards: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('General'));
    final background = tester
        .widget<Material>(
          find
              .ancestor(
                of: find.text('General'),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    final foreground = title.style!.color!;
    final contrast =
        (foreground.computeLuminance() + 0.05) /
        (background.computeLuminance() + 0.05);
    expect(contrast, greaterThan(4.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('board discovery distinguishes followed and unfollowed boards', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 22);
    await DriftHostedBoardRepository(db).upsertSubscription(
      BoardSubscription(
        subscriptionId: 'relay_general',
        forumHostId: 'relay',
        hostedBoardId: 'general',
        localBoardId: 'relay_general',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverScreen(
          db: db,
          localDid: 'did:plc:test',
          client: client(),
          startOnBoards: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('New Board'), findsOneWidget);
    expect(find.text('已訂閱'), findsOneWidget);
    expect(find.text('訂閱'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
  });

  testWidgets('follow control subscribes without opening the board', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 22);
    await DriftRemoteNodeRepository(db).create(
      RemoteNode(
        id: 'relay',
        name: 'Relay',
        url: 'https://relay.test',
        createdAt: now,
        updatedAt: now,
      ),
    );
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverScreen(
          db: db,
          localDid: 'did:plc:test',
          client: client(),
          startOnBoards: true,
          onOpenBoard: (_) => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('board_follow_new-board')));
    await tester.pumpAndSettle();

    expect(opened, isFalse);
    expect(find.text('New Board'), findsOneWidget);
    final subscriptions = await DriftHostedBoardRepository(
      db,
    ).listSubscriptions();
    expect(
      subscriptions.any((item) => item.hostedBoardId == 'new-board'),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('board_open_new-board')));
    await tester.pump();
    expect(opened, isTrue);
  });
}
