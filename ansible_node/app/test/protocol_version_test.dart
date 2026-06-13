import 'dart:convert';

import 'package:ansible_node/config/protocol.dart';
import 'package:ansible_node/l10n/user_facing_error.dart';
import 'package:ansible_node/services/forum_host_client.dart';
import 'package:ansible_node/services/relay_ops_client.dart';
import 'package:ansible_node/services/remote_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Phase 0 — API versioning: clients advertise their protocol version on
// every relay/appview request, 426 upgrade_required maps to friendly copy,
// and ops with an unknown future schema_version are skipped during sync.
// Widget assertions use zh-Hant copy because the test locale falls back to
// zh-Hant (see existing screen tests).
void main() {
  test('ForumHostClient sends the x-ansible-protocol header', () async {
    final client = ForumHostClient(
      baseUrl: 'http://relay.local',
      client: MockClient((request) async {
        expect(
          request.headers[AnsibleProtocol.headerName],
          '${AnsibleProtocol.currentVersion}',
        );
        return http.Response(jsonEncode({'host': 'relay.local'}), 200);
      }),
    );

    await client.getHostInfo();
  });

  test(
    'RelayOpsClient sends the protocol header and op schema_version',
    () async {
      final client = RelayOpsClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          expect(
            request.headers[AnsibleProtocol.headerName],
            '${AnsibleProtocol.currentVersion}',
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['schema_version'], 1);
          return http.Response(jsonEncode({'log_id': 7}), 202);
        }),
      );

      final entry = CrdtOpBuilder.createPost(
        authorDid: 'did:key:alice',
        entityId: 'post-1',
        boardId: 'board-1',
        threadId: 'thread-1',
        content: 'hello',
      );

      expect(await client.ingest(entry), 7);
    },
  );

  testWidgets('426 upgrade_required maps to the friendly update message', (
    tester,
  ) async {
    late String fromStatus;
    late String fromCode;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            fromStatus = userFacingError(
              context,
              const ForumHostException(
                statusCode: 426,
                error: 'upgrade_required',
                body: {
                  'error': 'upgrade_required',
                  'min_supported': 2,
                  'current': 2,
                },
              ),
            );
            fromCode = userFacingError(
              context,
              const RelayOpsException(
                statusCode: 426,
                error: 'upgrade_required',
                body: {'error': 'upgrade_required'},
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(fromStatus, contains('更新'));
    expect(fromStatus, isNot(contains('426')));
    expect(fromStatus, isNot(contains('upgrade_required')));
    expect(fromCode, fromStatus);
  });

  test(
    'delta sync skips ops with an unknown future schema_version',
    () async {
      final client = RelayApiClient(
        baseUrl: 'http://relay.local',
        client: MockClient((request) async {
          expect(
            request.headers[AnsibleProtocol.headerName],
            '${AnsibleProtocol.currentVersion}',
          );
          return http.Response(
            jsonEncode({
              'ops': [
                _deltaOp(opId: 'op-known', schemaVersion: 1),
                _deltaOp(
                  opId: 'op-future',
                  schemaVersion: AnsibleProtocol.currentVersion + 1,
                ),
                _deltaOp(opId: 'op-legacy', schemaVersion: null),
              ],
              'next_cursor': 3,
              'has_more': false,
            }),
            200,
          );
        }),
      );

      final delta = await client.getDelta();
      final activities = delta['activities'] as List<dynamic>;

      // The future-format op is skipped without throwing; known and legacy
      // (no schema_version) ops still sync.
      expect(activities, hasLength(2));
      final opIds = activities
          .map((entry) => entry['signedOp']['opId'])
          .toList();
      expect(opIds, ['op-known', 'op-legacy']);
    },
  );
}

Map<String, Object?> _deltaOp({required String opId, int? schemaVersion}) {
  return {
    'log_id': 1,
    'op_id': opId,
    'author_did': 'did:plc:alice',
    'entity_type': 'post',
    'entity_id': 'post-$opId',
    'op_type': 'insert',
    'payload': base64Encode(
      utf8.encode(jsonEncode({'boardId': 'b1', 'threadId': 't1'})),
    ),
    'signature': 'a' * 128,
    'public_key_hex': 'b' * 64,
    'received_at': '2026-06-13T12:00:00Z',
    if (schemaVersion != null) 'schema_version': schemaVersion,
  };
}
