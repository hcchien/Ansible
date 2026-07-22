import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ansible_did/ansible_did.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateBoardCryptoException implements Exception {
  const PrivateBoardCryptoException(this.code);
  final String code;

  @override
  String toString() => 'PrivateBoardCryptoException($code)';
}

abstract class BoardHardwareAgreement {
  Future<HardwareAgreementPublicKey> ensure(String boardId);
  Future<Uint8List> derive(String boardId, String peerPublicKeyHex);
}

class PlatformBoardHardwareAgreement implements BoardHardwareAgreement {
  @override
  Future<HardwareAgreementPublicKey> ensure(String boardId) async {
    final key = HardwarePurposeAgreementKey(boardId: boardId);
    return await key.load() ?? await key.generate();
  }

  @override
  Future<Uint8List> derive(String boardId, String peerPublicKeyHex) =>
      HardwarePurposeAgreementKey(boardId: boardId).derive(peerPublicKeyHex);
}

abstract class BoardEpochKeyStore {
  Future<void> put(String boardId, int epoch, List<int> key);
  Future<Uint8List?> get(String boardId, int epoch);
  Future<void> delete(String boardId, int epoch);
}

class SecureBoardEpochKeyStore implements BoardEpochKeyStore {
  const SecureBoardEpochKeyStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  String _key(String boardId, int epoch) {
    final boardHash = hashes.sha256.convert(utf8.encode(boardId));
    return 'elix.private-board.epoch.$boardHash.$epoch';
  }

  @override
  Future<void> put(String boardId, int epoch, List<int> key) {
    if (key.length != 32 || epoch < 1) {
      throw const PrivateBoardCryptoException('invalid_epoch_key');
    }
    return _storage.write(
      key: _key(boardId, epoch),
      value: base64UrlEncode(key).replaceAll('=', ''),
    );
  }

  @override
  Future<Uint8List?> get(String boardId, int epoch) async {
    final value = await _storage.read(key: _key(boardId, epoch));
    if (value == null) return null;
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != 32) {
      throw const PrivateBoardCryptoException('corrupt_epoch_key');
    }
    return decoded;
  }

  @override
  Future<void> delete(String boardId, int epoch) =>
      _storage.delete(key: _key(boardId, epoch));
}

class BoardEpochKeyEnvelope {
  const BoardEpochKeyEnvelope({
    required this.boardId,
    required this.epoch,
    required this.policyVersion,
    required this.recipientDeviceKeyId,
    required this.recipientPublicKeyHash,
    required this.senderPublicKeyHex,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final String boardId;
  final int epoch;
  final int policyVersion;
  final String recipientDeviceKeyId;
  final String recipientPublicKeyHash;
  final String senderPublicKeyHex;
  final String nonce;
  final String ciphertext;
  final String mac;

  String get senderPublicKeyHash =>
      hashes.sha256.convert(_hex(senderPublicKeyHex)).toString();

  Map<String, Object?> get aad => {
    'version': 1,
    'board_id': boardId,
    'epoch': epoch,
    'recipient_device_key_id': recipientDeviceKeyId,
    'recipient_public_key_hash': recipientPublicKeyHash,
    'sender_public_key_hash': senderPublicKeyHash,
    'policy_version': policyVersion,
  };

  Map<String, Object?> toJson() => {
    ...aad,
    'algorithm': 'P256-HKDF-SHA256+A256GCM',
    'sender_public_key_hex': senderPublicKeyHex,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  factory BoardEpochKeyEnvelope.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 ||
        json['algorithm'] != 'P256-HKDF-SHA256+A256GCM') {
      throw const PrivateBoardCryptoException('unsupported_key_envelope');
    }
    final envelope = BoardEpochKeyEnvelope(
      boardId: _requiredString(json, 'board_id'),
      epoch: _requiredPositiveInt(json, 'epoch'),
      policyVersion: _requiredPositiveInt(json, 'policy_version'),
      recipientDeviceKeyId: _requiredString(json, 'recipient_device_key_id'),
      recipientPublicKeyHash: _requiredString(
        json,
        'recipient_public_key_hash',
      ),
      senderPublicKeyHex: _requiredString(json, 'sender_public_key_hex'),
      nonce: _requiredString(json, 'nonce'),
      ciphertext: _requiredString(json, 'ciphertext'),
      mac: _requiredString(json, 'mac'),
    );
    if (json['sender_public_key_hash'] != envelope.senderPublicKeyHash) {
      throw const PrivateBoardCryptoException('invalid_sender_key');
    }
    return envelope;
  }
}

class PrivateBoardContentEnvelope {
  const PrivateBoardContentEnvelope({
    required this.boardId,
    required this.epoch,
    required this.policyVersion,
    required this.recordId,
    required this.recordType,
    required this.authorPairwiseId,
    required this.createdAt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final String boardId;
  final int epoch;
  final int policyVersion;
  final String recordId;
  final String recordType;
  final String authorPairwiseId;
  final DateTime createdAt;
  final String nonce;
  final String ciphertext;
  final String mac;

  Map<String, Object?> get aad => {
    'version': 1,
    'board_id': boardId,
    'epoch': epoch,
    'record_id': recordId,
    'record_type': recordType,
    'author_pairwise_id': authorPairwiseId,
    'created_at': _rfc3339Seconds(createdAt),
    'policy_version': policyVersion,
  };

  Map<String, Object?> toJson() => {
    ...aad,
    'algorithm': 'A256GCM',
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  factory PrivateBoardContentEnvelope.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 || json['algorithm'] != 'A256GCM') {
      throw const PrivateBoardCryptoException('unsupported_content_envelope');
    }
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    if (createdAt == null) {
      throw const PrivateBoardCryptoException('invalid_content_envelope');
    }
    return PrivateBoardContentEnvelope(
      boardId: _requiredString(json, 'board_id'),
      epoch: _requiredPositiveInt(json, 'epoch'),
      policyVersion: _requiredPositiveInt(json, 'policy_version'),
      recordId: _requiredString(json, 'record_id'),
      recordType: _requiredString(json, 'record_type'),
      authorPairwiseId: _requiredString(json, 'author_pairwise_id'),
      createdAt: createdAt.toUtc(),
      nonce: _requiredString(json, 'nonce'),
      ciphertext: _requiredString(json, 'ciphertext'),
      mac: _requiredString(json, 'mac'),
    );
  }
}

class PrivateBoardCryptoService {
  PrivateBoardCryptoService({
    BoardHardwareAgreement? hardwareAgreement,
    BoardEpochKeyStore? epochStore,
    Random? random,
  }) : _hardwareAgreement =
           hardwareAgreement ?? PlatformBoardHardwareAgreement(),
       _epochStore = epochStore ?? const SecureBoardEpochKeyStore(),
       _random = random ?? Random.secure();

  final BoardHardwareAgreement _hardwareAgreement;
  final BoardEpochKeyStore _epochStore;
  final Random _random;
  final _aes = AesGcm.with256bits();

  Future<HardwareAgreementPublicKey> ensureDeviceKey(String boardId) =>
      _hardwareAgreement.ensure(boardId);

  Future<Uint8List> createEpoch(String boardId, int epoch) async {
    if (boardId.isEmpty || epoch < 1) {
      throw const PrivateBoardCryptoException('invalid_epoch');
    }
    final key = _randomBytes(32);
    await _epochStore.put(boardId, epoch, key);
    return key;
  }

  Future<BoardEpochKeyEnvelope> wrapEpochKey({
    required String boardId,
    required int epoch,
    required int policyVersion,
    required String recipientDeviceKeyId,
    required String recipientPublicKeyHex,
  }) async {
    final epochKey = await _requiredEpochKey(boardId, epoch);
    final recipientBytes = _hex(recipientPublicKeyHex);
    if (recipientBytes.length != 65 || recipientBytes.first != 4) {
      throw const PrivateBoardCryptoException('invalid_recipient_key');
    }
    final recipientHash = hashes.sha256.convert(recipientBytes).toString();
    final senderPublic = await _hardwareAgreement.ensure(boardId);
    if (senderPublic.custody != IdentityKeyCustody.hardware) {
      throw const PrivateBoardCryptoException('hardware_key_required');
    }
    final shared = await _hardwareAgreement.derive(
      boardId,
      recipientPublicKeyHex,
    );
    final kek = await _deriveKek(SecretKey(shared), boardId, epoch);
    final partial = BoardEpochKeyEnvelope(
      boardId: boardId,
      epoch: epoch,
      policyVersion: policyVersion,
      recipientDeviceKeyId: recipientDeviceKeyId,
      recipientPublicKeyHash: recipientHash,
      senderPublicKeyHex: senderPublic.publicKeyHex,
      nonce: '',
      ciphertext: '',
      mac: '',
    );
    final nonce = _randomBytes(12);
    final sealed = await _aes.encrypt(
      epochKey,
      secretKey: kek,
      nonce: nonce,
      aad: utf8.encode(canonicalJson(partial.aad)),
    );
    return BoardEpochKeyEnvelope(
      boardId: boardId,
      epoch: epoch,
      policyVersion: policyVersion,
      recipientDeviceKeyId: recipientDeviceKeyId,
      recipientPublicKeyHash: recipientHash,
      senderPublicKeyHex: senderPublic.publicKeyHex,
      nonce: _b64(nonce),
      ciphertext: _b64(sealed.cipherText),
      mac: _b64(sealed.mac.bytes),
    );
  }

  Future<void> unwrapEpochKey(BoardEpochKeyEnvelope envelope) async {
    final local = await _hardwareAgreement.ensure(envelope.boardId);
    final localHash = hashes.sha256
        .convert(_hex(local.publicKeyHex))
        .toString();
    if (local.custody != IdentityKeyCustody.hardware ||
        localHash != envelope.recipientPublicKeyHash) {
      throw const PrivateBoardCryptoException('wrong_recipient_device');
    }
    final sharedBytes = await _hardwareAgreement.derive(
      envelope.boardId,
      envelope.senderPublicKeyHex,
    );
    final kek = await _deriveKek(
      SecretKey(sharedBytes),
      envelope.boardId,
      envelope.epoch,
    );
    final clear = await _decrypt(
      envelope.ciphertext,
      envelope.nonce,
      envelope.mac,
      kek,
      envelope.aad,
    );
    if (clear.length != 32) {
      throw const PrivateBoardCryptoException('invalid_epoch_key');
    }
    await _epochStore.put(envelope.boardId, envelope.epoch, clear);
  }

  Future<PrivateBoardContentEnvelope> encryptContent({
    required String boardId,
    required int epoch,
    required int policyVersion,
    required String recordId,
    required String recordType,
    required String authorPairwiseId,
    required DateTime createdAt,
    required Map<String, Object?> plaintext,
  }) async {
    final partial = PrivateBoardContentEnvelope(
      boardId: boardId,
      epoch: epoch,
      policyVersion: policyVersion,
      recordId: recordId,
      recordType: recordType,
      authorPairwiseId: authorPairwiseId,
      createdAt: createdAt.toUtc(),
      nonce: '',
      ciphertext: '',
      mac: '',
    );
    final nonce = _randomBytes(12);
    final sealed = await _aes.encrypt(
      utf8.encode(canonicalJson(plaintext)),
      secretKey: SecretKey(await _requiredEpochKey(boardId, epoch)),
      nonce: nonce,
      aad: utf8.encode(canonicalJson(partial.aad)),
    );
    return PrivateBoardContentEnvelope(
      boardId: boardId,
      epoch: epoch,
      policyVersion: policyVersion,
      recordId: recordId,
      recordType: recordType,
      authorPairwiseId: authorPairwiseId,
      createdAt: createdAt.toUtc(),
      nonce: _b64(nonce),
      ciphertext: _b64(sealed.cipherText),
      mac: _b64(sealed.mac.bytes),
    );
  }

  Future<Map<String, Object?>> decryptContent(
    PrivateBoardContentEnvelope envelope,
  ) async {
    final clear = await _decrypt(
      envelope.ciphertext,
      envelope.nonce,
      envelope.mac,
      SecretKey(await _requiredEpochKey(envelope.boardId, envelope.epoch)),
      envelope.aad,
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) {
      throw const PrivateBoardCryptoException('invalid_plaintext');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<Uint8List> _requiredEpochKey(String boardId, int epoch) async {
    final key = await _epochStore.get(boardId, epoch);
    if (key == null) {
      throw const PrivateBoardCryptoException('epoch_key_unavailable');
    }
    return key;
  }

  Future<SecretKey> _deriveKek(SecretKey shared, String boardId, int epoch) {
    final salt = hashes.sha256
        .convert(utf8.encode('$boardId\u0000$epoch'))
        .bytes;
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode('elix-private-board-key-wrap-v1'),
    );
  }

  Future<Uint8List> _decrypt(
    String ciphertext,
    String nonce,
    String mac,
    SecretKey key,
    Map<String, Object?> aad,
  ) async {
    try {
      return Uint8List.fromList(
        await _aes.decrypt(
          SecretBox(
            _unb64(ciphertext),
            nonce: _unb64(nonce),
            mac: Mac(_unb64(mac)),
          ),
          secretKey: key,
          aad: utf8.encode(canonicalJson(aad)),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const PrivateBoardCryptoException('authentication_failed');
    }
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
}

String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List) return value.map(_canonical).toList(growable: false);
  return value;
}

String _b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
Uint8List _unb64(String value) => base64Url.decode(base64Url.normalize(value));

Uint8List _hex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw const PrivateBoardCryptoException('invalid_hex');
  }
  return Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw const PrivateBoardCryptoException('invalid_envelope');
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw const PrivateBoardCryptoException('invalid_envelope');
}

String _rfc3339Seconds(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d{3}Z$'), 'Z');
