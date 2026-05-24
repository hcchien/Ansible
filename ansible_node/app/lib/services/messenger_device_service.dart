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
  final MessengerSecretStore secretStore;
  final MessengerRelayClient relayClient;
  final DateTime Function() now;

  MessengerDeviceService({
    required this.repository,
    MessengerCryptoBridge? crypto,
    MessengerSecretStore? secretStore,
    MessengerRelayClient? relayClient,
    DateTime Function()? now,
  }) : crypto = crypto ?? RustMessengerCryptoBridge(),
       secretStore = secretStore ?? _secretStoreFor(crypto),
       relayClient = relayClient ?? MessengerRelayClient(),
       now = now ?? (() => DateTime.now().toUtc());

  Future<MessengerDeviceRecord> ensurePublishedDevice({
    required String subjectDid,
    required DidSigner didSigner,
  }) async {
    final existing = await repository.localDeviceForSubject(subjectDid);
    final device = existing == null
        ? await _createAndPublishDevice(subjectDid, didSigner)
        : await _secureExistingDevice(existing);
    await _replenishPreKeysIfNeeded(device, didSigner);
    return device;
  }

  Future<MessengerDeviceRecord> _createAndPublishDevice(
    String subjectDid,
    DidSigner didSigner,
  ) async {
    final bundle = await crypto.createDevice(subjectDid);
    final record = await _recordFromBundle(bundle, now());
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
    var unpublished = await repository.unpublishedPreKeys(record.deviceId);
    unpublished = await _secureExistingPreKeys(record, unpublished);
    if (unpublished.length >= minUnpublishedPreKeys) return;

    final generated = await crypto.generatePreKeys(
      _bundleFromRecord(record),
      preKeyReplenishCount,
    );
    if (generated.isEmpty) return;

    final createdAt = now();
    final preKeyRecords = <MessengerPreKeyRecord>[];
    for (final preKey in generated) {
      preKeyRecords.add(
        MessengerPreKeyRecord(
          deviceId: record.deviceId,
          preKeyId: preKey.preKeyId,
          publicKey: preKey.publicKey,
          privateKeyRef: await _secureSecret(
            namespace: 'prekey.${record.deviceId}',
            secretId: '${preKey.preKeyId}',
            value: preKey.privateKeyRef,
          ),
          createdAt: createdAt,
        ),
      );
    }
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

  Future<MessengerDeviceRecord> _recordFromBundle(
    MessengerDeviceBundle bundle,
    DateTime createdAt,
  ) async {
    return MessengerDeviceRecord(
      subjectDid: bundle.subjectDid,
      deviceId: bundle.deviceId,
      identityKeyPublic: bundle.identityKeyPublic,
      identityKeyPrivateRef: await _secureSecret(
        namespace: 'device.${bundle.deviceId}',
        secretId: 'identity',
        value: bundle.identityKeyPrivateRef,
      ),
      isLocal: true,
      signedPreKeyId: bundle.signedPreKeyId,
      signedPreKeyPublic: bundle.signedPreKeyPublic,
      signedPreKeyPrivateRef: await _secureSecret(
        namespace: 'device.${bundle.deviceId}',
        secretId: 'signed_pre_key',
        value: bundle.signedPreKeyPrivateRef,
      ),
      signedPreKeySignature: bundle.signedPreKeySignature,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  Future<MessengerDeviceRecord> _secureExistingDevice(
    MessengerDeviceRecord record,
  ) async {
    final identityRef = record.identityKeyPrivateRef == null
        ? null
        : await _secureSecret(
            namespace: 'device.${record.deviceId}',
            secretId: 'identity',
            value: record.identityKeyPrivateRef!,
          );
    final signedPreKeyRef = record.signedPreKeyPrivateRef == null
        ? null
        : await _secureSecret(
            namespace: 'device.${record.deviceId}',
            secretId: 'signed_pre_key',
            value: record.signedPreKeyPrivateRef!,
          );
    if (identityRef == record.identityKeyPrivateRef &&
        signedPreKeyRef == record.signedPreKeyPrivateRef) {
      return record;
    }
    final secured = MessengerDeviceRecord(
      subjectDid: record.subjectDid,
      deviceId: record.deviceId,
      identityKeyPublic: record.identityKeyPublic,
      identityKeyPrivateRef: identityRef,
      isLocal: true,
      signedPreKeyId: record.signedPreKeyId,
      signedPreKeyPublic: record.signedPreKeyPublic,
      signedPreKeyPrivateRef: signedPreKeyRef,
      signedPreKeySignature: record.signedPreKeySignature,
      bindingJson: record.bindingJson,
      bindingSignature: record.bindingSignature,
      createdAt: record.createdAt,
      updatedAt: now(),
    );
    await repository.upsertLocalDevice(secured);
    return secured;
  }

  Future<List<MessengerPreKeyRecord>> _secureExistingPreKeys(
    MessengerDeviceRecord record,
    List<MessengerPreKeyRecord> preKeys,
  ) async {
    final secured = <MessengerPreKeyRecord>[];
    var changed = false;
    for (final preKey in preKeys) {
      final privateKeyRef = preKey.privateKeyRef;
      if (privateKeyRef == null ||
          secretStore.isSecretReference(privateKeyRef)) {
        secured.add(preKey);
        continue;
      }
      changed = true;
      secured.add(
        MessengerPreKeyRecord(
          deviceId: preKey.deviceId,
          preKeyId: preKey.preKeyId,
          publicKey: preKey.publicKey,
          privateKeyRef: await _secureSecret(
            namespace: 'prekey.${record.deviceId}',
            secretId: '${preKey.preKeyId}',
            value: privateKeyRef,
          ),
          createdAt: preKey.createdAt,
          publishedAt: preKey.publishedAt,
          consumedAt: preKey.consumedAt,
        ),
      );
    }
    if (changed) {
      await repository.savePreKeys(secured);
    }
    return secured;
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

  Future<String> _secureSecret({
    required String namespace,
    required String secretId,
    required String value,
  }) async {
    if (secretStore.isSecretReference(value)) return value;
    return secretStore.putSecret(
      namespace: namespace,
      secretId: secretId,
      secret: value,
    );
  }

  static MessengerSecretStore _secretStoreFor(MessengerCryptoBridge? crypto) {
    if (crypto is RustMessengerCryptoBridge) return crypto.secretStore;
    return const SecureStorageMessengerSecretStore();
  }
}
