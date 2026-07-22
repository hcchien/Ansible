import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/private_board_crypto_service.dart';
import 'package:ansible_node/services/private_board_op_factory.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'wraps an epoch to a board-scoped device and encrypts content',
    () async {
      final senderStore = _MemoryEpochStore();
      final receiverStore = _MemoryEpochStore();
      final senderHardware = _FakeHardwareAgreement('sender');
      final receiverHardware = _FakeHardwareAgreement('receiver');
      final sender = PrivateBoardCryptoService(
        hardwareAgreement: senderHardware,
        epochStore: senderStore,
        random: Random(1),
      );
      final receiver = PrivateBoardCryptoService(
        hardwareAgreement: receiverHardware,
        epochStore: receiverStore,
        random: Random(2),
      );
      final boardId = 'https://relay.example/boards/private-1';
      await sender.createEpoch(boardId, 1);
      final receiverPublic = await receiver.ensureDeviceKey(boardId);

      final wrapped = await sender.wrapEpochKey(
        boardId: boardId,
        epoch: 1,
        policyVersion: 7,
        recipientDeviceKeyId: 'device-key-1',
        recipientPublicKeyHex: receiverPublic.publicKeyHex,
      );
      await receiver.unwrapEpochKey(wrapped);
      final encrypted = await sender.encryptContent(
        boardId: boardId,
        epoch: 1,
        policyVersion: 7,
        recordId: 'post-1',
        recordType: 'post',
        authorPairwiseId: 'board-member-opaque-1',
        createdAt: DateTime.utc(2026, 7, 22, 14),
        plaintext: const {'title': 'Private', 'body': 'Only members see this.'},
      );

      expect(await receiver.decryptContent(encrypted), {
        'body': 'Only members see this.',
        'title': 'Private',
      });
      expect(wrapped.toJson().toString(), isNot(contains('Only members')));
      expect(encrypted.toJson().toString(), isNot(contains('Private')));
    },
  );

  test('AAD tampering and missing epochs fail closed', () async {
    final store = _MemoryEpochStore();
    final service = PrivateBoardCryptoService(
      epochStore: store,
      random: Random(3),
    );
    await service.createEpoch('board-a', 1);
    final encrypted = await service.encryptContent(
      boardId: 'board-a',
      epoch: 1,
      policyVersion: 2,
      recordId: 'post-1',
      recordType: 'post',
      authorPairwiseId: 'member-1',
      createdAt: DateTime.utc(2026, 7, 22),
      plaintext: const {'body': 'secret'},
    );
    final tampered = PrivateBoardContentEnvelope(
      boardId: encrypted.boardId,
      epoch: encrypted.epoch,
      policyVersion: 3,
      recordId: encrypted.recordId,
      recordType: encrypted.recordType,
      authorPairwiseId: encrypted.authorPairwiseId,
      createdAt: encrypted.createdAt,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
      mac: encrypted.mac,
    );

    expect(
      () => service.decryptContent(tampered),
      throwsA(
        isA<PrivateBoardCryptoException>().having(
          (error) => error.code,
          'code',
          'authentication_failed',
        ),
      ),
    );
    expect(
      () => service.encryptContent(
        boardId: 'board-a',
        epoch: 2,
        policyVersion: 3,
        recordId: 'post-2',
        recordType: 'post',
        authorPairwiseId: 'member-1',
        createdAt: DateTime.utc(2026, 7, 22),
        plaintext: const {'body': 'new epoch'},
      ),
      throwsA(isA<PrivateBoardCryptoException>()),
    );
  });

  test('canonical JSON sorts nested object keys', () {
    expect(
      canonicalJson({
        'z': 1,
        'a': {'y': 2, 'b': 3},
      }),
      '{"a":{"b":3,"y":2},"z":1}',
    );
  });

  test('private-board op contains routing metadata but no plaintext', () async {
    final store = _MemoryEpochStore();
    final crypto = PrivateBoardCryptoService(
      epochStore: store,
      random: Random(4),
    );
    await crypto.createEpoch('private-board', 3);
    final now = DateTime.utc(2026, 7, 22, 12);
    final board = HostedBoardProjection(
      localBoardId: 'local-private',
      forumHostId: 'relay',
      hostedBoardId: 'private-board',
      canonicalBoardUri: 'https://relay.example/boards/private-board',
      remoteSlug: 'private-board',
      localSlug: 'private-board',
      title: 'Private',
      contentVisibility: 'end_to_end_encrypted',
      encryptionEpoch: 3,
      encryptionState: 'ready',
      accessPolicyVersion: 9,
      createdAt: now,
      updatedAt: now,
    );
    final op =
        await PrivateBoardOpFactory(
          crypto: crypto,
          pairwiseSubject: () async => 'did:jwk:opaque-pairwise',
        ).createPost(
          board: board,
          authorDid: 'did:elix:author',
          entityId: 'post-secret',
          threadId: 'thread-secret',
          content: 'highly confidential text',
          createdAt: now,
        );

    final payload = utf8.decode(base64Decode(op.payload));
    expect(payload, contains('private_envelope'));
    expect(payload, contains('private-board'));
    expect(payload, isNot(contains('highly confidential text')));
  });
}

class _MemoryEpochStore implements BoardEpochKeyStore {
  final values = <String, Uint8List>{};

  String _id(String boardId, int epoch) => '$boardId\u0000$epoch';

  @override
  Future<void> put(String boardId, int epoch, List<int> key) async {
    values[_id(boardId, epoch)] = Uint8List.fromList(key);
  }

  @override
  Future<Uint8List?> get(String boardId, int epoch) async {
    final value = values[_id(boardId, epoch)];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String boardId, int epoch) async {
    values.remove(_id(boardId, epoch));
  }
}

class _FakeHardwareAgreement implements BoardHardwareAgreement {
  _FakeHardwareAgreement(this.deviceId);

  final String deviceId;
  final _publicKeys = <String, String>{};

  @override
  Future<HardwareAgreementPublicKey> ensure(String boardId) async {
    final publicKey = _publicKeys[boardId] ??= _public(boardId);
    return HardwareAgreementPublicKey(
      publicKeyHex: publicKey,
      custody: IdentityKeyCustody.hardware,
      hardwareSecurityLevel: 'test-hardware',
    );
  }

  @override
  Future<Uint8List> derive(String boardId, String peerPublicKeyHex) async {
    final own = _publicKeys[boardId] ?? (throw StateError('missing key'));
    final pair = [own, peerPublicKeyHex]..sort();
    return Uint8List.fromList(
      hashes.sha256.convert(utf8.encode(pair.join('|'))).bytes,
    );
  }

  String _public(String boardId) {
    final first = hashes.sha256
        .convert(utf8.encode('$deviceId:$boardId:x'))
        .bytes;
    final second = hashes.sha256
        .convert(utf8.encode('$deviceId:$boardId:y'))
        .bytes;
    return _hex([4, ...first, ...second]);
  }
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
