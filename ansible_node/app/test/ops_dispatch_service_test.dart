import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/op_signature_payload.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/services/relay_ops_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('signAndEnqueue signs using opId plus payload', () async {
    final repo = InMemoryOpsQueueRepository();
    final service = OpsDispatchService(
      repository: repo,
      signer: _RecordingSigner(),
      relayClient: RelayOpsClient(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
    );

    final entry = CrdtOpBuilder.createPost(
      authorDid: 'did:key:z6MkTest',
      entityId: 'post-1',
      boardId: 'board-1',
      threadId: 'thread-1',
      content: 'hello',
    );

    final signed = await service.signAndEnqueue(entry);
    final queued = await repo.listPending();
    final payload =
        jsonDecode(utf8.decode(base64Decode(entry.payload)))
            as Map<String, dynamic>;

    expect(
      signed.signature,
      'signed:${OpSignaturePayload.fromQueueEntry(entry)}',
    );
    expect(queued.single.signature, signed.signature);
    expect(payload['boardId'], 'board-1');
    expect(payload['threadId'], 'thread-1');
    expect(payload['content'], 'hello');
  });

  test('sign fails closed when the production signer is unavailable', () async {
    final service = OpsDispatchService(
      repository: InMemoryOpsQueueRepository(),
      signer: _FailingSigner(),
      relayClient: RelayOpsClient(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
    );

    expect(
      () => service.sign(_entry()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('insecure signing fallback is disabled'),
        ),
      ),
    );
  });

  test('flushPending marks accepted ops as synced', () async {
    final repo = InMemoryOpsQueueRepository();
    await repo.enqueue(_entry());

    final service = OpsDispatchService(
      repository: repo,
      signer: _RecordingSigner(),
      relayClient: RelayOpsClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['op_id'], 'op-1');
          expect(body['author_did'], 'did:key:z6MkTest');
          return http.Response(
            jsonEncode({'accepted': true, 'log_id': 1}),
            202,
          );
        }),
      ),
    );

    await service.flushPending();

    expect(await repo.countPending(), 0);
    expect((await repo.listAll()).single.status, 'synced');
  });

  test('flushPending marks malformed ops as rejected', () async {
    final repo = InMemoryOpsQueueRepository();
    await repo.enqueue(_entry());

    final service = OpsDispatchService(
      repository: repo,
      signer: _RecordingSigner(),
      relayClient: RelayOpsClient(
        client: MockClient((_) async {
          return http.Response(jsonEncode({'error': 'invalid_value'}), 422);
        }),
      ),
    );

    await service.flushPending();

    expect(await repo.countPending(), 0);
    expect((await repo.listAll()).single.status, 'rejected');
  });

  test(
    'flushPending keeps unverified DID ops pending for re-anchoring',
    () async {
      final repo = InMemoryOpsQueueRepository();
      await repo.enqueue(_entry());

      final service = OpsDispatchService(
        repository: repo,
        signer: _RecordingSigner(),
        relayClient: RelayOpsClient(
          client: MockClient((_) async {
            return http.Response(jsonEncode({'error': 'unverified_did'}), 401);
          }),
        ),
      );

      await service.flushPending();

      expect(await repo.countPending(), 1);
      expect((await repo.listAll()).single.status, 'pending');
    },
  );
}

OpsQueueEntry _entry() {
  return OpsQueueEntry(
    opId: 'op-1',
    authorDid: 'did:key:z6MkTest',
    entityType: 'post',
    entityId: 'post-1',
    opType: 'insert',
    payload: 'aGVsbG8=',
    signature: 'sig',
    createdAt: DateTime(2026, 5, 2),
  );
}

class _RecordingSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return Ed25519Signature('signed:${utf8.decode(message)}');
  }
}

class _FailingSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    throw StateError('key unavailable');
  }
}
