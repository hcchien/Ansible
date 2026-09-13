import 'dart:convert';
import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_node/services/ops_dispatch_service.dart';
import 'package:ansible_node/services/relay_ops_client.dart';
import 'package:ansible_node/services/delivery_diagnostics.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class CancelledSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async =>
      throw StateError('cancelled');
}

void main() {
  test(
    'backfill keeps original author time separate from operation creation',
    () {
      final old = DateTime.utc(2025, 1, 2);
      final op = CrdtOpBuilder.createMurmur(
        authorDid: 'did:a',
        entityId: 'old',
        text: 'history',
        contentCreatedAt: old,
      );
      final payload = CrdtOpBuilder.decodePayload(op.payload);
      expect(payload['createdAt'], old.toIso8601String());
      expect(payload['publishedAt'], old.toIso8601String());
      expect(op.createdAt.isAfter(old), isTrue);
    },
  );
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  late AppDatabase db;
  late DriftOpsQueueRepository queue;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    queue = DriftOpsQueueRepository(db);
  });
  tearDown(() => db.close());
  OpsQueueEntry entry(String id) => CrdtOpBuilder.createComment(
    authorDid: 'did:a',
    entityId: id,
    targetId: 'm',
    content: 'private diagnostic exclusion',
  ).copyWith(signature: 'signed');

  test(
    'cancelled authorization retains exactly one durable operation',
    () async {
      final op = entry('a');
      final service = OpsDispatchService(
        repository: queue,
        signer: CancelledSigner(),
      );
      await expectLater(service.signAndEnqueue(op), throwsStateError);
      await expectLater(service.signAndEnqueue(op), throwsStateError);
      final restored = await DriftOpsQueueRepository(db).listDelivery('did:a');
      expect(restored.single.opId, op.opId);
      expect(restored.single.status, 'awaiting_authorization');
      expect(await queue.listPending(), isEmpty);
    },
  );

  test(
    'stale composer cannot overwrite a cancelled delivery decision',
    () async {
      final op = entry('cancelled');
      await queue.retainForAuthorization(op);
      await queue.cancelUnattempted(op.opId, 'did:a');
      final restored = await queue.retainForAuthorization(op);
      expect(restored.status, 'cancelled');
      await expectLater(
        OpsDispatchService(
          repository: queue,
          signer: CancelledSigner(),
        ).signAndEnqueue(op),
        throwsStateError,
      );
      expect((await queue.deliveryOp(op.opId))!.status, 'cancelled');
      expect(await queue.listPending(), isEmpty);
    },
  );

  test('cancel wins against stale signing and stale dispatch', () async {
    final op = entry('a');
    await queue.enqueue(op.copyWith(status: 'awaiting_authorization'));
    await queue.cancelUnattempted(op.opId, 'did:a');
    expect(await queue.prepareRetry(op), isFalse);
    expect(await queue.claimForSend(op.opId), isFalse);
    expect((await queue.deliveryOp(op.opId))!.status, 'cancelled');
  });

  test(
    'attempt persists before network failure, retries same ID after reopening',
    () async {
      final op = entry('a');
      await queue.enqueue(op);
      final ids = <String>[];
      var fail = true;
      final client = RelayOpsClient(
        baseUrl: 'https://relay.example',
        client: MockClient((request) async {
          ids.add((jsonDecode(request.body) as Map)['op_id'] as String);
          expect((await queue.deliveryOp(op.opId))!.sentAt, isNotNull);
          if (fail) throw http.ClientException('secret token and post content');
          return http.Response('{"error":"duplicate_op_id"}', 409);
        }),
      );
      await OpsDispatchService(
        repository: queue,
        signer: CancelledSigner(),
        relayClient: client,
      ).flushPending();
      expect((await queue.deliveryOp(op.opId))!.status, 'blocked');
      await queue.cancelUnattempted(op.opId, 'did:a');
      expect((await queue.deliveryOp(op.opId))!.status, 'blocked');
      fail = false;
      final restored = DriftOpsQueueRepository(db);
      await restored.prepareRetry((await restored.deliveryOp(op.opId))!);
      await OpsDispatchService(
        repository: restored,
        signer: CancelledSigner(),
        relayClient: client,
      ).flushPending();
      expect(ids, [op.opId, op.opId]);
      expect((await restored.listDelivery('did:a')).single.status, 'synced');
      final report = jsonEncode(await DeliveryDiagnostics.shared.read('did:a'));
      expect(report, contains('network_or_authorization_failed'));
      expect(report, isNot(contains('secret token')));
      expect(report, isNot(contains('private diagnostic exclusion')));
    },
  );

  test('other 409 conflicts never become Relay acceptance', () async {
    final op = entry('a');
    await queue.enqueue(op);
    final service = OpsDispatchService(
      repository: queue,
      signer: CancelledSigner(),
      relayClient: RelayOpsClient(
        client: MockClient(
          (_) async => http.Response('{"error":"identity_conflict"}', 409),
        ),
      ),
    );
    await service.flushPending();
    expect((await queue.deliveryOp(op.opId))!.status, isNot('synced'));
  });
}
