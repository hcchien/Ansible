import 'dart:convert';

import 'package:ansible_node/services/discovery_client.dart';
import 'package:ansible_node/widgets/public_profile_status_card.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase db;
  const did = 'did:elix:me';
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> localProfile() async {
    await DriftContactRepository(db).upsertContact(
      ContactRecord(
        subjectDid: did,
        handle: 'me.elix.cool',
        displayName: 'New name',
        source: 'self',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  }

  DiscoveryClient client(
    Future<http.Response> Function(http.Request) handler,
  ) => DiscoveryClient(
    appViewBaseUrl: 'https://appview.test',
    relayBaseUrl: '',
    client: MockClient(handler),
  );

  Future<void> pump(WidgetTester tester, DiscoveryClient client) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PublicProfileStatusCard(db: db, did: did, client: client),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a filled local profile is not proof of public indexing', (
    tester,
  ) async {
    await localProfile();
    await pump(
      tester,
      client((request) async {
        expect(Uri.decodeComponent(request.url.path), '/api/v1/profiles/$did');
        expect(request.method, 'GET');
        return http.Response('{}', 404);
      }),
    );
    expect(find.text('尚未找到這份公開檔案'), findsOneWidget);
    expect(find.text('已可被搜尋'), findsNothing);
  });

  testWidgets('network failure is unknown, retry observes an indexed profile', (
    tester,
  ) async {
    var online = false;
    await pump(
      tester,
      client(
        (_) async => online
            ? http.Response(
                jsonEncode({'did': did, 'handle': 'me.elix.cool'}),
                200,
              )
            : http.Response('{}', 503),
      ),
    );
    expect(find.text('暫時無法確認公開狀態'), findsOneWidget);
    expect(find.text('讓大家找到你'), findsNothing);
    online = true;
    await tester.tap(find.byKey(const Key('public_profile_check')));
    await tester.pumpAndSettle();
    expect(find.text('已可被搜尋'), findsOneWidget);
  });

  testWidgets(
    'indexed old name does not claim that local edits are published',
    (tester) async {
      await localProfile();
      await pump(
        tester,
        client(
          (_) async => http.Response(
            jsonEncode({
              'did': did,
              'handle': 'me.elix.cool',
              'display_name': 'Old name',
            }),
            200,
          ),
        ),
      );
      expect(find.text('已公開，本機有待發布的變更'), findsOneWidget);
      expect(find.text('已可被搜尋'), findsNothing);
    },
  );

  testWidgets('lookup of a different DID cannot confirm publication', (
    tester,
  ) async {
    await pump(
      tester,
      client(
        (_) async => http.Response(
          jsonEncode({
            'did': 'did:elix:someone-else',
            'handle': 'me.elix.cool',
          }),
          200,
        ),
      ),
    );
    expect(find.text('暫時無法確認公開狀態'), findsOneWidget);
  });
}
