import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/recovery_veto_service.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_node/widgets/recovery_veto_alert.dart';

void main() {
  const did = 'did:elix:test';
  const pendingBody =
      '{"did":"did:elix:test","reason":"recovery","schema_version":1}';

  MockClient relayWith({
    bool pending = true,
    List<Map<String, Object?>>? vetoCalls,
    int vetoStatus = 200,
  }) {
    return MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/pending')) {
        if (!pending) {
          return http.Response('{"error":"no_pending_anchor"}', 404);
        }
        return http.Response(
          jsonEncode({
            'anchor_cid': 'sha256:pending-cid',
            'reason': 'recovery',
            'grace_until': '2026-07-06T00:00:00Z',
            'canonical_body': pendingBody,
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/anchor/veto')) {
        vetoCalls?.add(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
        return http.Response(
          vetoStatus == 200
              ? '{"state":"vetoed","frozen":true}'
              : '{"error":"invalid_signature"}',
          vetoStatus,
        );
      }
      return http.Response('{"error":"unexpected"}', 500);
    });
  }

  RecoveryVetoService serviceWith(MockClient client) => RecoveryVetoService(
        relayClient: RelayAnchorClient(
          baseUrl: 'http://relay.test',
          client: client,
        ),
        identityKey: InMemoryIdentityKey(
          // Deterministic test key (any 64-hex seed works for signing).
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );

  test('checkPending returns the grace-window anchor', () async {
    final service = serviceWith(relayWith());
    final pending = await service.checkPending(did);
    expect(pending, isNotNull);
    expect(pending!.anchorCid, 'sha256:pending-cid');
    expect(pending.canonicalBody, pendingBody);
    expect(pending.graceUntil, isNotNull);
  });

  test('checkPending returns null when none / on transport errors', () async {
    expect(await serviceWith(relayWith(pending: false)).checkPending(did),
        isNull);

    final broken = RecoveryVetoService(
      relayClient: RelayAnchorClient(
        baseUrl: 'http://relay.test',
        client: MockClient((_) async => throw Exception('down')),
      ),
      identityKey: InMemoryIdentityKey(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );
    expect(await broken.checkPending(did), isNull);
  });

  test('veto signs the served canonical body and posts it', () async {
    final vetoCalls = <Map<String, Object?>>[];
    final service = serviceWith(relayWith(vetoCalls: vetoCalls));
    final pending = await service.checkPending(did);

    await service.veto(did: did, pending: pending!);

    expect(vetoCalls, hasLength(1));
    expect(vetoCalls.single['did'], did);
    expect(vetoCalls.single['pending_anchor_cid'], 'sha256:pending-cid');
    final sig = vetoCalls.single['veto_sig'] as String;
    expect(sig, isNotEmpty);
    // Ed25519 signature hex is 128 chars.
    expect(sig.length, 128);
  });

  testWidgets('alert dialog vetoes on confirm', (tester) async {
    final vetoCalls = <Map<String, Object?>>[];
    final service = serviceWith(relayWith(vetoCalls: vetoCalls));
    final pending = await service.checkPending(did);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRecoveryVetoAlert(
                context,
                did: did,
                pending: pending!,
                vetoService: service,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('偵測到帳號復原請求'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recovery_veto_confirm')));
    await tester.pumpAndSettle();

    expect(vetoCalls, hasLength(1));
    expect(find.text('偵測到帳號復原請求'), findsNothing);
  });

  testWidgets('alert dialog surfaces veto failure inline', (tester) async {
    final service = serviceWith(relayWith(vetoStatus: 401));
    final pending = await service.checkPending(did);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRecoveryVetoAlert(
                context,
                did: did,
                pending: pending!,
                vetoService: service,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery_veto_confirm')));
    await tester.pumpAndSettle();

    // Dialog stays open with the error; the user can retry or dismiss.
    expect(find.byKey(const Key('recovery_veto_error')), findsOneWidget);
    expect(find.text('偵測到帳號復原請求'), findsOneWidget);
  });
}
