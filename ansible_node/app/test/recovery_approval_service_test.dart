import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ansible_node/services/identity_anchor_service.dart';
import 'package:ansible_node/services/recovery_approval_service.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';

/// In-memory device key store for the approving (old) device.
class _MemoryDeviceKeyStore implements DeviceKeyStore {
  DeviceKey? stored;

  _MemoryDeviceKeyStore(this.stored);

  @override
  Future<DeviceKey?> load() async => stored;

  @override
  Future<void> save(DeviceKey key) async => stored = key;

  @override
  Future<void> clear() async => stored = null;
}

void main() {
  const handle = 'tris.elix.cool';

  late IdentityAnchor activeAnchor;
  late String did;
  late DeviceKey oldDeviceKey;
  late IdentityKey oldIdentityKey;

  /// Seeds the "previous" world: an active anchor whose enrolled device is
  /// [oldDeviceKey] — exactly what the approving device holds.
  Future<void> seedActiveAnchor() async {
    oldIdentityKey = InMemoryIdentityKey(
      // 64 hex chars = 32-byte Ed25519 seed.
      'cc' * 1 + 'cc' * 31,
    );
    final identityKeyHex = await oldIdentityKey.publicKeyHex();
    did = deriveDidElix(identityKey: identityKeyHex, handle: handle);
    oldDeviceKey = await DeviceKey.generate();
    final enrolledAt = DateTime.utc(2026, 6, 1);
    final attestationSig = await oldIdentityKey.sign(
      oldDeviceKey.deviceAttestationMessage(
        custodyClass: CustodyClass.software,
        enrolledAt: enrolledAt,
      ),
    );
    final record = oldDeviceKey.toDeviceRecord(
      custodyClass: CustodyClass.software,
      enrolledAt: enrolledAt,
      attestationSigHex: attestationSig,
    );
    final unsigned = IdentityAnchor(
      did: did,
      handle: handle,
      identityKey: identityKeyHex,
      alsoKnownAs: buildAlsoKnownAs(
        handle: handle,
        identityKeyHex: identityKeyHex,
      ),
      custodyClass: CustodyClass.software,
      devices: [record],
      prevAnchorCid: null,
      reason: AnchorReason.initial,
      createdAt: enrolledAt,
      sig: '',
    );
    final sig = await oldIdentityKey.sign(
      utf8.encode(unsigned.canonicalBodyJson()),
    );
    activeAnchor = IdentityAnchor.fromMap({
      ...unsigned.toCanonicalMap(),
      'sig': sig,
    });
  }

  MockClient relay({List<Map<String, Object?>>? submissions}) {
    return MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.contains('/identity/anchor/')) {
        return http.Response(jsonEncode(activeAnchor.toCanonicalMap()), 200);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/identity/anchor')) {
        submissions?.add(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
        return http.Response(
          jsonEncode({
            'state': 'pending',
            'anchor_cid': 'sha256:pending',
            'grace_until': '2026-07-06T00:00:00Z',
          }),
          202,
        );
      }
      return http.Response('{"error":"unexpected"}', 500);
    });
  }

  RecoveryApprovalService service(MockClient client, {DeviceKey? approverKey}) {
    return RecoveryApprovalService(
      relayClient: RelayAnchorClient(
        baseUrl: 'http://relay.test',
        client: client,
      ),
      deviceKeyStore: _MemoryDeviceKeyStore(approverKey),
      approvalIdentityKey: oldIdentityKey,
      replacementIdentityKey: InMemoryIdentityKey('dd' * 32),
      now: () => DateTime.utc(2026, 7, 3),
    );
  }

  setUp(seedActiveAnchor);

  test(
    'full round trip: build → QR → parse → approve submits a valid proof',
    () async {
      final submissions = <Map<String, Object?>>[];
      final client = relay(submissions: submissions);

      // New device builds the request.
      final newDevice = service(client);
      final request = await newDevice.buildRequest(did: did, handle: handle);
      expect(request, isNotNull);
      expect(request!.anchor.reason, AnchorReason.recovery);
      expect(request.anchor.prevAnchorCid, activeAnchor.computeCid());
      expect(request.newKeyFingerprint, contains('…'));

      // QR round trip.
      final parsed = RecoveryApprovalService.parseRequest(
        request.toQrPayload(),
      );
      expect(parsed, isNotNull);
      expect(parsed!.computeCid(), request.anchor.computeCid());

      // Old (enrolled) device approves.
      final oldDevice = service(client, approverKey: oldDeviceKey);
      final result = await oldDevice.approve(localDid: did, anchor: parsed);
      expect(result.isPending, isTrue);
      expect(result.graceUntil, isNotNull);

      // The submission carries the anchor + a recovery_proof that verifies
      // against the active identity key over the canonical body. The device
      // key is enrollment metadata, not the recovery authority.
      expect(submissions, hasLength(1));
      final submitted = submissions.single;
      expect(submitted['did'], did);
      expect(submitted['reason'], 'recovery');
      final proof = submitted['recovery_proof'] as String;
      expect(
        await Ed25519Keys.verify(
          publicKeyHex: activeAnchor.identityKey,
          message: utf8.encode(parsed.canonicalBodyJson()),
          sigHex: proof,
        ),
        isTrue,
      );
    },
  );

  test('refuses a request for someone else\'s identity', () async {
    final client = relay();
    final request = await service(
      client,
    ).buildRequest(did: did, handle: handle);
    final oldDevice = service(client, approverKey: oldDeviceKey);

    await expectLater(
      oldDevice.approve(localDid: 'did:elix:notme', anchor: request!.anchor),
      throwsA(
        isA<RecoveryApprovalException>().having(
          (e) => e.reason,
          'reason',
          'different_identity',
        ),
      ),
    );
  });

  test(
    'refuses a stale request that does not chain onto the active anchor',
    () async {
      final client = relay();
      final request = await service(
        client,
      ).buildRequest(did: did, handle: handle);

      final stale = IdentityAnchor.fromMap({
        ...request!.anchor.toCanonicalMap(),
        'prev_anchor_cid': 'sha256:stale',
      });

      final oldDevice = service(client, approverKey: oldDeviceKey);
      await expectLater(
        oldDevice.approve(localDid: did, anchor: stale),
        throwsA(
          isA<RecoveryApprovalException>().having(
            (e) => e.reason,
            'reason',
            'stale_request',
          ),
        ),
      );
    },
  );

  test(
    'active identity key can approve without an exportable device key',
    () async {
      final submissions = <Map<String, Object?>>[];
      final client = relay(submissions: submissions);
      final request = await service(
        client,
      ).buildRequest(did: did, handle: handle);

      final oldDevice = service(client); // no legacy device private key
      final result = await oldDevice.approve(
        localDid: did,
        anchor: request!.anchor,
      );
      expect(result.isPending, isTrue);
      expect(submissions, hasLength(1));
    },
  );

  test('non-recovery or malformed QR payloads parse to null', () {
    expect(RecoveryApprovalService.parseRequest('not json'), isNull);
    expect(
      RecoveryApprovalService.parseRequest(jsonEncode({'v': 1, 't': 'other'})),
      isNull,
    );
    expect(
      RecoveryApprovalService.parseRequest(
        jsonEncode({'v': 1, 't': RecoveryApprovalService.qrType, 'anchor': 3}),
      ),
      isNull,
    );
  });
}
