import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/screens/notification_settings_screen.dart';
import 'package:ansible_node/services/push_registration_service.dart';
import 'package:ansible_node/services/platform_capabilities.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async =>
      const Ed25519Signature('deadbeef');
}

class _FakeTokenProvider implements PushTokenProvider {
  const _FakeTokenProvider();

  @override
  Future<PushDeviceToken?> currentToken() async =>
      const PushDeviceToken(token: 'token-123', platform: 'fcm');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PushRegistrationService', () {
    test('register posts a sorted, signed payload and accepts 201', () async {
      late Map<String, dynamic> sent;
      late String path;
      final service = PushRegistrationService(
        baseUrl: 'https://relay.example',
        tokenProvider: const _FakeTokenProvider(),
        signer: _FakeSigner(),
        client: MockClient((request) async {
          path = request.url.path;
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 201);
        }),
      );

      final registered = await service.register(
        did: 'did:plc:user',
        categories: ['reply', 'messenger'],
      );

      expect(registered, isTrue);
      expect(path, '/api/v1/push/tokens');
      expect(sent['request_signature'], 'deadbeef');
      expect(sent['subject_did'], 'did:plc:user');
      expect(sent['platform'], 'fcm');
      expect(sent['push_token'], 'token-123');
      expect(sent['categories'], ['messenger', 'reply']); // sorted
      // Canonical key order (signature appended after signing).
      final keys = sent.keys.toList();
      expect(keys.sublist(0, keys.length - 1), [
        'categories',
        'device_id',
        'platform',
        'push_token',
        'registered_at',
        'subject_did',
      ]);
    });

    test('register returns false when no platform token exists', () async {
      final service = PushRegistrationService(
        baseUrl: 'https://relay.example',
        signer: _FakeSigner(),
        client: MockClient(
          (_) async => fail('must not call the relay without a token'),
        ),
      );

      expect(await service.register(did: 'did:plc:user', categories: const []),
          isFalse);
    });

    test('unregister posts to the unregister endpoint', () async {
      late String path;
      late Map<String, dynamic> sent;
      final service = PushRegistrationService(
        baseUrl: 'https://relay.example',
        tokenProvider: const _FakeTokenProvider(),
        signer: _FakeSigner(),
        client: MockClient((request) async {
          path = request.url.path;
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await service.unregister(did: 'did:plc:user');

      expect(path, '/api/v1/push/tokens/unregister');
      expect(sent['subject_did'], 'did:plc:user');
      expect(sent['request_signature'], 'deadbeef');
    });

    test('error statuses surface as PushRegistrationException', () async {
      final service = PushRegistrationService(
        baseUrl: 'https://relay.example',
        tokenProvider: const _FakeTokenProvider(),
        signer: _FakeSigner(),
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'error': 'invalid_signature'}), 401),
        ),
      );

      await expectLater(
        service.register(did: 'did:plc:user', categories: const ['reply']),
        throwsA(isA<PushRegistrationException>()),
      );
    });
  });

  group('push settings toggle', () {
    testWidgets('enabling push registers with the active relay', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());
      final now = DateTime.now().toUtc();
      await DriftRemoteNodeRepository(db).create(
        RemoteNode(
          id: 'node-1',
          name: 'Elix Relay',
          url: 'https://relay.example',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            db: db,
            did: 'did:plc:user',
            platformCapabilities:
                PlatformCapabilities.forPlatform(ElixPlatform.ios),
            pushServiceFactory: (baseUrl) {
              expect(baseUrl, 'https://relay.example');
              return PushRegistrationService(
                baseUrl: baseUrl,
                tokenProvider: const _FakeTokenProvider(),
                signer: _FakeSigner(),
                client: MockClient((request) async {
                  calls.add(request.url.path);
                  return http.Response(jsonEncode({'ok': true}), 201);
                }),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final pushToggle = find.byKey(
        const Key('notification_toggle_push_wake'),
      );
      expect(pushToggle, findsOneWidget);
      await tester.ensureVisible(pushToggle);
      await tester.tap(
        find.descendant(of: pushToggle, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(calls, ['/api/v1/push/tokens']);
    });

    testWidgets('push section is hidden without db/did context', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: NotificationSettingsScreen()),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('notification_toggle_push_wake')),
        findsNothing,
      );
    });

    testWidgets('desktop keeps local notification settings but hides wake push', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            db: db,
            did: 'did:elix:desktop',
            platformCapabilities:
                PlatformCapabilities.forPlatform(ElixPlatform.macos),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('notification_toggle_push_wake')),
        findsNothing,
      );
      expect(find.byType(Switch), findsWidgets);
    });
  });
}
