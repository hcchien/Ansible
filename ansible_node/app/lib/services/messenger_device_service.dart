import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';

import 'messenger_crypto_bridge.dart';
import 'messenger_relay_client.dart';

class MessengerDeviceService {
  static const int minUnpublishedPreKeys = 5;
  static const int preKeyReplenishCount = 20;

  final MessengerRepository repository;
  final MessengerCryptoBridge crypto;
  final MessengerRelayClient relayClient;
  final DateTime Function() now;

  MessengerDeviceService({
    required this.repository,
    MessengerCryptoBridge? crypto,
    MessengerRelayClient? relayClient,
    DateTime Function()? now,
  }) : crypto = crypto ?? RustMessengerCryptoBridge(),
       relayClient = relayClient ?? MessengerRelayClient(),
       now = now ?? (() => DateTime.now().toUtc());

  Future<MessengerDeviceRecord> ensurePublishedDevice({
    required String subjectDid,
    required DidSigner didSigner,
  }) async {
    final existing = await repository.localDeviceForSubject(subjectDid);
    final device =
        existing ?? await _createAndPublishDevice(subjectDid, didSigner);
    await _replenishPreKeysIfNeeded(device, didSigner);
    return device;
  }

  Future<MessengerDeviceRecord> _createAndPublishDevice(
    String subjectDid,
    DidSigner didSigner,
  ) async {
    final bundle = await crypto.createDevice(subjectDid);
    final record = _recordFromBundle(bundle, now());
    await repository.upsertLocalDevice(record);

    final binding = _binding(record);
    final bindingSignature = await _signJson(didSigner, binding);
    await relayClient.publishDevice(
      subjectDid: record.subjectDid,
      deviceId: record.deviceId,
      bundle: _publicBundle(record),
      binding: binding,
      bindingSignature: bindingSignature,
    );

    return record;
  }

  Future<void> _replenishPreKeysIfNeeded(
    MessengerDeviceRecord record,
    DidSigner didSigner,
  ) async {
    final unpublished = await repository.unpublishedPreKeys(record.deviceId);
    if (unpublished.length >= minUnpublishedPreKeys) return;

    final generated = await crypto.generatePreKeys(
      _bundleFromRecord(record),
      preKeyReplenishCount,
    );
    if (generated.isEmpty) return;

    final createdAt = now();
    final preKeyRecords = [
      for (final preKey in generated)
        MessengerPreKeyRecord(
          deviceId: record.deviceId,
          preKeyId: preKey.preKeyId,
          publicKey: preKey.publicKey,
          privateKeyRef: preKey.privateKeyRef,
          createdAt: createdAt,
        ),
    ];
    await repository.savePreKeys(preKeyRecords);

    final relayPreKeys = [
      for (final preKey in generated)
        {'pre_key_id': preKey.preKeyId, 'pre_key': preKey.publicKey},
    ];
    final requestSignature = await _signJson(didSigner, {
      'subject_did': record.subjectDid,
      'device_id': record.deviceId,
      'pre_keys': relayPreKeys,
    });
    await relayClient.publishPreKeys(
      subjectDid: record.subjectDid,
      deviceId: record.deviceId,
      preKeys: relayPreKeys,
      requestSignature: requestSignature,
    );

    for (final preKey in generated) {
      await repository.markPreKeyPublished(record.deviceId, preKey.preKeyId);
    }
  }

  MessengerDeviceRecord _recordFromBundle(
    MessengerDeviceBundle bundle,
    DateTime createdAt,
  ) {
    return MessengerDeviceRecord(
      subjectDid: bundle.subjectDid,
      deviceId: bundle.deviceId,
      identityKeyPublic: bundle.identityKeyPublic,
      identityKeyPrivateRef: bundle.identityKeyPrivateRef,
      isLocal: true,
      signedPreKeyId: bundle.signedPreKeyId,
      signedPreKeyPublic: bundle.signedPreKeyPublic,
      signedPreKeyPrivateRef: bundle.signedPreKeyPrivateRef,
      signedPreKeySignature: bundle.signedPreKeySignature,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  MessengerDeviceBundle _bundleFromRecord(MessengerDeviceRecord record) {
    return MessengerDeviceBundle(
      subjectDid: record.subjectDid,
      deviceId: record.deviceId,
      identityKeyPublic: record.identityKeyPublic,
      identityKeyPrivateRef: record.identityKeyPrivateRef ?? '',
      signedPreKeyId: record.signedPreKeyId ?? 0,
      signedPreKeyPublic: record.signedPreKeyPublic ?? '',
      signedPreKeyPrivateRef: record.signedPreKeyPrivateRef ?? '',
      signedPreKeySignature: record.signedPreKeySignature ?? '',
    );
  }

  Map<String, Object?> _publicBundle(MessengerDeviceRecord record) {
    return {
      'messenger_identity_key': record.identityKeyPublic,
      'signed_pre_key_id': record.signedPreKeyId,
      'signed_pre_key': record.signedPreKeyPublic,
      'signed_pre_key_signature': record.signedPreKeySignature,
    };
  }

  Map<String, Object?> _binding(MessengerDeviceRecord record) {
    return {
      'type': 'io.trisaura.messengerDeviceBinding',
      'version': 1,
      'subject_did': record.subjectDid,
      'device_id': record.deviceId,
      'messenger_identity_key': record.identityKeyPublic,
      'signed_pre_key_id': record.signedPreKeyId,
      'signed_pre_key': record.signedPreKeyPublic,
    };
  }

  Future<String> _signJson(
    DidSigner didSigner,
    Map<String, Object?> value,
  ) async {
    final signature = await didSigner.sign(utf8.encode(_canonicalJson(value)));
    return signature.hex;
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return '{${entries.map((entry) {
        return '${jsonEncode(entry.key.toString())}:${_canonicalJson(entry.value)}';
      }).join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}
