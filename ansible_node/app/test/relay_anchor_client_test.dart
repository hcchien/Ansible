import 'dart:convert';

import 'package:ansible_node/config/protocol.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

IdentityAnchor _anchor({
  AnchorReason reason = AnchorReason.initial,
  String? prevAnchorCid,
  String? deviceSig,
}) {
  return IdentityAnchor(
    did: 'did:plc:alice',
    handle: 'alice.elix.cool',
    identityKey: 'ab' * 32,
    custodyClass: CustodyClass.software,
    devices: const [],
    prevAnchorCid: prevAnchorCid,
    reason: reason,
    createdAt: DateTime.utc(2026, 6, 13),
    sig: 'cd' * 64,
    deviceSig: deviceSig,
  );
}

void main() {
  group('RelayAnchorClient.submitAnchor', () {
    test('initial → 201 active, sends the anchor body + protocol header',
        () async {
      final anchor = _anchor();
      late http.Request seen;
      final client = RelayAnchorClient(
        baseUrl: 'http://relay.local/root',
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({'state': 'active', 'anchor_cid': anchor.computeCid()}),
            201,
          );
        }),
      );

      final result = await client.submitAnchor(anchor);

      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'http://relay.local/root/api/v1/identity/anchor',
      );
      expect(seen.headers['content-type'], 'application/json');
      expect(
        seen.headers[AnsibleProtocol.headerName],
        '${AnsibleProtocol.currentVersion}',
      );
      // The request body is the anchor object JSON (canonical body + sig), no
      // recovery_proof sibling for a plain submit.
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['type'], IdentityAnchor.typeName);
      expect(body['did'], 'did:plc:alice');
      expect(body['sig'], 'cd' * 64);
      expect(body.containsKey('recovery_proof'), isFalse);

      expect(result.state, AnchorState.active);
      expect(result.statusCode, 201);
      expect(result.anchorCid, anchor.computeCid());
      expect(result.isPending, isFalse);
    });

    test('rotation → 200 active', () async {
      final anchor = _anchor(
        reason: AnchorReason.rotation,
        prevAnchorCid: 'sha256:deadbeef',
        deviceSig: 'ef' * 64,
      );
      final client = RelayAnchorClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['reason'], 'rotation');
          expect(body['device_sig'], 'ef' * 64);
          return http.Response(
            jsonEncode({'state': 'active', 'anchor_cid': anchor.computeCid()}),
            200,
          );
        }),
      );

      final result = await client.submitAnchor(anchor);
      expect(result.state, AnchorState.active);
      expect(result.statusCode, 200);
    });

    test('recovery → 202 pending with grace_until + recovery_proof sibling',
        () async {
      final anchor = _anchor(
        reason: AnchorReason.recovery,
        prevAnchorCid: 'sha256:deadbeef',
      );
      final client = RelayAnchorClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // recovery_proof rides as a SIBLING of the anchor body.
          expect(body['recovery_proof'], 'aa' * 64);
          expect(body['reason'], 'recovery');
          return http.Response(
            jsonEncode({
              'state': 'pending',
              'anchor_cid': anchor.computeCid(),
              'grace_until': '2026-06-16T00:00:00Z',
            }),
            202,
          );
        }),
      );

      final result =
          await client.submitAnchor(anchor, recoveryProof: 'aa' * 64);
      expect(result.state, AnchorState.pending);
      expect(result.isPending, isTrue);
      expect(result.statusCode, 202);
      expect(result.graceUntil, DateTime.utc(2026, 6, 16));
    });

    test('401 invalid_signature maps to a typed exception', () async {
      final client = RelayAnchorClient(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({'error': 'invalid_signature'}),
            401,
          );
        }),
      );
      expect(
        () => client.submitAnchor(_anchor()),
        throwsA(isA<RelayAnchorException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.error, 'error', 'invalid_signature')),
      );
    });

    test('409 conflict maps to a typed exception', () async {
      final client = RelayAnchorClient(
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'conflict'}), 409);
        }),
      );
      expect(
        () => client.submitAnchor(_anchor()),
        throwsA(isA<RelayAnchorException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.error, 'error', 'conflict')),
      );
    });

    test('423 account_frozen maps to a typed exception', () async {
      final client = RelayAnchorClient(
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'account_frozen'}), 423);
        }),
      );
      expect(
        () => client.submitAnchor(_anchor()),
        throwsA(isA<RelayAnchorException>()
            .having((e) => e.statusCode, 'statusCode', 423)
            .having((e) => e.error, 'error', 'account_frozen')),
      );
    });
  });

  group('RelayAnchorClient.fetchActiveAnchor', () {
    test('200 returns the parsed anchor object', () async {
      final anchor = _anchor();
      final wire = anchor.toCanonicalMap()
        ..['anchor_cid'] = anchor.computeCid()
        ..['state'] = 'active';
      final client = RelayAnchorClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/api/v1/identity/anchor/did%3Aplc%3Aalice',
          );
          return http.Response(jsonEncode(wire), 200);
        }),
      );
      final got = await client.fetchActiveAnchor('did:plc:alice');
      expect(got, isNotNull);
      expect(got!.did, 'did:plc:alice');
      expect(got.computeCid(), anchor.computeCid());
    });

    test('404 returns null', () async {
      final client = RelayAnchorClient(
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'anchor_not_found'}), 404);
        }),
      );
      expect(await client.fetchActiveAnchor('did:plc:nobody'), isNull);
    });

    test('423 throws account_frozen', () async {
      final client = RelayAnchorClient(
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'account_frozen'}), 423);
        }),
      );
      expect(
        () => client.fetchActiveAnchor('did:plc:frozen'),
        throwsA(isA<RelayAnchorException>()
            .having((e) => e.statusCode, 'statusCode', 423)),
      );
    });
  });

  group('RelayAnchorClient.vetoPendingAnchor', () {
    test('posts the veto payload and succeeds on 200', () async {
      late http.Request seen;
      final client = RelayAnchorClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({'state': 'vetoed', 'frozen': true}),
            200,
          );
        }),
      );
      await client.vetoPendingAnchor(
        did: 'did:plc:alice',
        pendingAnchorCid: 'sha256:pending',
        vetoSig: 'ff' * 64,
      );
      expect(seen.url.path, '/api/v1/identity/anchor/veto');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['did'], 'did:plc:alice');
      expect(body['pending_anchor_cid'], 'sha256:pending');
      expect(body['veto_sig'], 'ff' * 64);
    });

    test('401 invalid_signature throws', () async {
      final client = RelayAnchorClient(
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'invalid_signature'}), 401);
        }),
      );
      expect(
        () => client.vetoPendingAnchor(
          did: 'did:plc:alice',
          pendingAnchorCid: 'sha256:pending',
          vetoSig: 'ff' * 64,
        ),
        throwsA(isA<RelayAnchorException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });
}
