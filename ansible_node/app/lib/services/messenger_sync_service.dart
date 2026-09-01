import 'dart:convert';
import 'dart:typed_data';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';

import 'messenger_crypto_bridge.dart';
import 'messenger_device_service.dart';
import 'messenger_relay_client.dart';
import 'notification_projector.dart';

class MessengerSyncService {
  final MessengerRepository repository;
  final ContactRepository? contactRepository;
  final MessengerDeviceService deviceService;
  final MessengerRelayClient relayClient;
  final MessengerCryptoBridge crypto;
  final MessengerSecretStore secretStore;
  final DidSigner didSigner;

  /// Optional local notification projection: emits `messenger_message`
  /// notifications for decrypted inbound messages. The projector reuses the
  /// inbox's blocked-contact checks, so blocked senders never notify.
  final NotificationProjector? notificationProjector;
  final DateTime Function() now;
  final String Function() idGenerator;

  MessengerSyncService({
    required this.repository,
    this.contactRepository,
    required this.deviceService,
    required this.relayClient,
    required this.crypto,
    required this.didSigner,
    this.notificationProjector,
    MessengerSecretStore? secretStore,
    DateTime Function()? now,
    String Function()? idGenerator,
  }) : secretStore = secretStore ?? _secretStoreFor(crypto),
       now = now ?? (() => DateTime.now().toUtc()),
       idGenerator =
           idGenerator ??
           (() => 'msg_${DateTime.now().toUtc().microsecondsSinceEpoch}');

  Future<MessengerDeviceRecord> ensureReady({required String subjectDid}) {
    return deviceService.ensurePublishedDevice(
      subjectDid: subjectDid,
      didSigner: didSigner,
    );
  }

  Future<MessengerMessageRecord> sendText({
    required String senderDid,
    required String recipientDid,
    required String text,
  }) async {
    final localDevice = await deviceService.ensurePublishedDevice(
      subjectDid: senderDid,
      didSigner: didSigner,
    );
    final recipientBundle = await relayClient.fetchPreKeyBundle(recipientDid);
    if (recipientBundle.devices.isEmpty) {
      throw StateError('No messenger devices available for $recipientDid');
    }

    final createdAt = now().toUtc();
    final messageId = idGenerator();
    final plaintextRef = await _secureSecret(
      namespace: 'message.$messageId',
      secretId: 'plaintext',
      value: text,
    );
    final pending = MessengerMessageRecord(
      messageId: messageId,
      conversationId: recipientDid,
      direction: MessengerMessageDirection.outbound,
      status: MessengerMessageStatus.pending,
      plaintext: plaintextRef,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await repository.saveMessage(pending);

    String? firstCiphertext;
    String? firstCiphertextType;
    var deliveredDevices = 0;
    for (var index = 0; index < recipientBundle.devices.length; index += 1) {
      final remoteDevice = recipientBundle.devices[index];
      if (remoteDevice.oneTimePreKeyId == null ||
          remoteDevice.oneTimePreKey == null) {
        continue;
      }
      await _pinRemoteDevice(recipientDid, remoteDevice, createdAt);
      final encrypted = await crypto.encryptInitialMessage(
        MessengerEncryptRequest(
          localDevice: await _bundleFromRecord(localDevice),
          remoteBundle: _remoteBundleJson(recipientBundle, remoteDevice),
          plaintext: Uint8List.fromList(utf8.encode(text)),
        ),
      );
      final ciphertext = base64Encode(encrypted.ciphertext);
      firstCiphertext ??= ciphertext;
      firstCiphertextType ??= encrypted.ciphertextType;
      await repository.saveSession(
        MessengerSessionRecord(
          localDeviceId: localDevice.deviceId,
          remoteDid: recipientDid,
          remoteDeviceId: remoteDevice.deviceId,
          sessionState: await _secureSecret(
            namespace:
                'session.${localDevice.deviceId}.${remoteDevice.deviceId}',
            secretId: 'state',
            value: encrypted.updatedSessionState,
          ),
          updatedAt: createdAt,
        ),
      );

      final envelopeId = recipientBundle.devices.length == 1
          ? messageId
          : '$messageId.${remoteDevice.deviceId}';
      final signedPayload = {
        'message_id': envelopeId,
        'sender_did': senderDid,
        'sender_device_id': localDevice.deviceId,
        'recipient_did': recipientDid,
        'recipient_device_id': remoteDevice.deviceId,
        'ciphertext_type': encrypted.ciphertextType,
        'ciphertext': ciphertext,
        'protocol_version': encrypted.protocolVersion,
        'created_at': createdAt.toIso8601String(),
      };
      await relayClient.sendMessage(
        messageId: envelopeId,
        senderDid: senderDid,
        senderDeviceId: localDevice.deviceId,
        recipientDid: recipientDid,
        recipientDeviceId: remoteDevice.deviceId,
        ciphertextType: encrypted.ciphertextType,
        ciphertext: ciphertext,
        protocolVersion: encrypted.protocolVersion,
        createdAt: createdAt,
        requestSignature: await _signJson(signedPayload),
      );
      deliveredDevices += 1;
    }

    if (deliveredDevices == 0) {
      throw StateError('No one-time pre-keys available for $recipientDid');
    }

    final sent = MessengerMessageRecord(
      messageId: pending.messageId,
      conversationId: pending.conversationId,
      direction: pending.direction,
      status: MessengerMessageStatus.sent,
      plaintext: plaintextRef,
      ciphertextType: firstCiphertextType,
      ciphertext: firstCiphertext,
      createdAt: pending.createdAt,
      updatedAt: now().toUtc(),
    );
    await repository.saveMessage(sent);
    return _resolveMessage(sent);
  }

  Future<MessengerPullResult> pullAndDecrypt({
    required String recipientDid,
  }) async {
    final localDevice = await deviceService.ensurePublishedDevice(
      subjectDid: recipientDid,
      didSigner: didSigner,
    );
    final cursor = await repository.mailboxCursorFor(localDevice.deviceId);
    final mailbox = await relayClient.pullMailbox(
      recipientDid: localDevice.subjectDid,
      recipientDeviceId: localDevice.deviceId,
      requestSignature: await _signJson({
        'recipient_did': localDevice.subjectDid,
        'recipient_device_id': localDevice.deviceId,
      }),
      cursor: cursor,
    );

    var receivedMessages = 0;
    var messageRequests = 0;
    for (final message in mailbox.messages) {
      final result = await _decryptAndStore(localDevice, message);
      if (result.received) receivedMessages += 1;
      if (result.messageRequest) messageRequests += 1;
    }

    final nextCursor = mailbox.nextCursor;
    if (nextCursor != null && nextCursor.isNotEmpty) {
      await repository.saveMailboxCursor(localDevice.deviceId, nextCursor);
    }
    return MessengerPullResult(
      receivedMessages: receivedMessages,
      messageRequests: messageRequests,
    );
  }

  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) async {
    final messages = await repository.messagesForConversation(conversationId);
    final resolved = <MessengerMessageRecord>[];
    for (final message in messages) {
      resolved.add(await _resolveMessage(message));
    }
    return resolved;
  }

  Future<_DecryptStoreResult> _decryptAndStore(
    MessengerDeviceRecord localDevice,
    MessengerMailboxMessage message,
  ) async {
    final receivedAt = message.createdAt ?? now().toUtc();
    try {
      final plaintext = await crypto.decryptInboundMessage(
        MessengerDecryptRequest(
          localDevice: await _bundleFromRecord(localDevice),
          ciphertext: MessengerCiphertextEnvelope(
            protocolVersion: message.protocolVersion,
            ciphertextType: message.ciphertextType,
            ciphertext: base64Decode(message.ciphertext),
            updatedSessionState: '',
          ),
        ),
      );
      final plaintextBody = utf8.decode(plaintext.body);
      final consumedPreKeyId = _oneTimePreKeyId(message.ciphertext);
      final lifecycleRepository =
          repository is MessengerPreKeyLifecycleRepository
          ? repository as MessengerPreKeyLifecycleRepository
          : null;
      if (consumedPreKeyId != null && lifecycleRepository != null) {
        await lifecycleRepository.markPreKeyConsumed(
          localDevice.deviceId,
          consumedPreKeyId,
        );
      }
      final updatedAt = now().toUtc();
      await repository.saveMessage(
        MessengerMessageRecord(
          messageId: message.messageId,
          conversationId: message.senderDid,
          direction: MessengerMessageDirection.inbound,
          status: MessengerMessageStatus.received,
          plaintext: await _secureSecret(
            namespace: 'message.${message.messageId}',
            secretId: 'plaintext',
            value: plaintextBody,
          ),
          ciphertextType: message.ciphertextType,
          ciphertext: message.ciphertext,
          createdAt: receivedAt,
          updatedAt: updatedAt,
        ),
      );
      final isRequest = await _recordMessageRequestIfNeeded(
        message.senderDid,
        updatedAt,
      );
      // Local notification (dedup-keyed by message id, so re-pulls never
      // duplicate). Blocked senders are excluded inside the projector.
      await notificationProjector?.onMessengerMessage(
        senderDid: message.senderDid,
        messageId: message.messageId,
        receivedAt: receivedAt,
      );
      await repository.saveSession(
        MessengerSessionRecord(
          localDeviceId: localDevice.deviceId,
          remoteDid: message.senderDid,
          remoteDeviceId: message.senderDeviceId,
          sessionState: await _secureSecret(
            namespace:
                'session.${localDevice.deviceId}.${message.senderDeviceId}',
            secretId: 'state',
            value: plaintext.updatedSessionState,
          ),
          updatedAt: updatedAt,
        ),
      );
      await relayClient.ackMessage(
        messageId: message.messageId,
        recipientDid: localDevice.subjectDid,
        recipientDeviceId: localDevice.deviceId,
        requestSignature: await _signJson({
          'message_id': message.messageId,
          'recipient_did': localDevice.subjectDid,
          'recipient_device_id': localDevice.deviceId,
        }),
      );
      return _DecryptStoreResult(received: true, messageRequest: isRequest);
    } catch (_) {
      final failedAt = now().toUtc();
      await repository.saveMessage(
        MessengerMessageRecord(
          messageId: message.messageId,
          conversationId: message.senderDid,
          direction: MessengerMessageDirection.inbound,
          status: MessengerMessageStatus.decryptFailed,
          ciphertextType: message.ciphertextType,
          ciphertext: message.ciphertext,
          createdAt: receivedAt,
          updatedAt: failedAt,
        ),
      );
      return const _DecryptStoreResult(received: false, messageRequest: false);
    }
  }

  Future<bool> _recordMessageRequestIfNeeded(
    String senderDid,
    DateTime timestamp,
  ) async {
    final contacts = contactRepository;
    if (contacts == null) return false;
    final existing = await contacts.contactForDid(senderDid);
    if (existing == null) {
      await contacts.upsertContact(
        ContactRecord(
          subjectDid: senderDid,
          relationship: ContactRelationship.invite,
          source: 'message_request',
          trustState: ContactTrustState.unverified,
          createdAt: timestamp,
          updatedAt: timestamp,
          lastResolvedAt: timestamp,
        ),
      );
      return true;
    }
    if (existing.relationship == ContactRelationship.unknown) {
      await contacts.upsertContact(
        existing.copyWith(
          relationship: ContactRelationship.invite,
          source: 'message_request',
          updatedAt: timestamp,
          lastResolvedAt: timestamp,
        ),
      );
      return true;
    }
    return existing.relationship == ContactRelationship.invite ||
        existing.source == 'message_request';
  }

  Future<MessengerDeviceBundle> _bundleFromRecord(
    MessengerDeviceRecord record,
  ) async {
    final preKeys = repository is MessengerPreKeyLifecycleRepository
        ? await (repository as MessengerPreKeyLifecycleRepository)
              .unconsumedPreKeys(record.deviceId)
        : const <MessengerPreKeyRecord>[];
    return MessengerDeviceBundle(
      subjectDid: record.subjectDid,
      deviceId: record.deviceId,
      identityKeyPublic: record.identityKeyPublic,
      identityKeyPrivateRef: record.identityKeyPrivateRef ?? '',
      signedPreKeyId: record.signedPreKeyId ?? 0,
      signedPreKeyPublic: record.signedPreKeyPublic ?? '',
      signedPreKeyPrivateRef: record.signedPreKeyPrivateRef ?? '',
      signedPreKeySignature: record.signedPreKeySignature ?? '',
      oneTimePreKeys: [
        for (final preKey in preKeys)
          if (preKey.privateKeyRef != null)
            MessengerCryptoPreKey(
              preKeyId: preKey.preKeyId,
              publicKey: preKey.publicKey,
              privateKeyRef: preKey.privateKeyRef!,
            ),
      ],
    );
  }

  int? _oneTimePreKeyId(String encodedCiphertext) {
    try {
      final envelope = jsonDecode(utf8.decode(base64Decode(encodedCiphertext)));
      if (envelope is Map && envelope['one_time_pre_key_id'] is int) {
        return envelope['one_time_pre_key_id'] as int;
      }
    } catch (_) {
      // A crypto provider may use a non-JSON wire envelope. In that case it
      // must expose consumed-key metadata before this provider is enabled.
    }
    return null;
  }

  Future<void> _pinRemoteDevice(
    String subjectDid,
    MessengerPreKeyBundleDevice device,
    DateTime timestamp,
  ) async {
    final trustRepository = repository is MessengerRemoteDeviceTrustRepository
        ? repository as MessengerRemoteDeviceTrustRepository
        : null;
    final existing = await trustRepository?.remoteDeviceById(device.deviceId);
    if (existing != null &&
        (existing.subjectDid != subjectDid ||
            existing.identityKeyPublic != device.messengerIdentityKey)) {
      throw MessengerIdentityKeyChanged(
        subjectDid: subjectDid,
        deviceId: device.deviceId,
      );
    }
    await repository.upsertRemoteDevice(
      MessengerDeviceRecord(
        subjectDid: subjectDid,
        deviceId: device.deviceId,
        identityKeyPublic: device.messengerIdentityKey,
        signedPreKeyId: device.signedPreKeyId,
        signedPreKeyPublic: device.signedPreKey,
        signedPreKeySignature: device.signedPreKeySignature,
        bindingJson: device.binding.isEmpty ? null : jsonEncode(device.binding),
        bindingSignature: device.bindingSignature,
        createdAt: existing?.createdAt ?? timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  Map<String, Object?> _remoteBundleJson(
    MessengerPreKeyBundleResponse bundle,
    MessengerPreKeyBundleDevice device,
  ) {
    return {
      'subject_did': bundle.subjectDid,
      'device_id': device.deviceId,
      'identity_key': device.messengerIdentityKey,
      'messenger_identity_key': device.messengerIdentityKey,
      'signed_pre_key_id': device.signedPreKeyId,
      'signed_pre_key': device.signedPreKey,
      'signed_pre_key_signature': device.signedPreKeySignature,
      if (device.oneTimePreKeyId != null)
        'one_time_pre_key_id': device.oneTimePreKeyId,
      if (device.oneTimePreKey != null)
        'one_time_pre_key': device.oneTimePreKey,
      if (device.binding.isNotEmpty) 'binding': device.binding,
      if (device.bindingSignature != null)
        'binding_signature': device.bindingSignature,
    };
  }

  Future<String> _signJson(Map<String, Object?> value) async {
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

  Future<MessengerMessageRecord> _resolveMessage(
    MessengerMessageRecord message,
  ) async {
    final plaintext = message.plaintext;
    return MessengerMessageRecord(
      messageId: message.messageId,
      conversationId: message.conversationId,
      direction: message.direction,
      status: message.status,
      plaintext: plaintext == null
          ? null
          : await secretStore.resolveSecret(plaintext),
      ciphertextType: message.ciphertextType,
      ciphertext: message.ciphertext,
      createdAt: message.createdAt,
      updatedAt: message.updatedAt,
    );
  }

  static MessengerSecretStore _secretStoreFor(MessengerCryptoBridge crypto) {
    if (crypto is RustMessengerCryptoBridge) return crypto.secretStore;
    return const SecureStorageMessengerSecretStore();
  }
}

class MessengerPullResult {
  const MessengerPullResult({
    required this.receivedMessages,
    required this.messageRequests,
  });

  final int receivedMessages;
  final int messageRequests;
}

class MessengerIdentityKeyChanged implements Exception {
  const MessengerIdentityKeyChanged({
    required this.subjectDid,
    required this.deviceId,
  });

  final String subjectDid;
  final String deviceId;

  @override
  String toString() =>
      'MessengerIdentityKeyChanged(subjectDid: $subjectDid, deviceId: $deviceId)';
}

class _DecryptStoreResult {
  const _DecryptStoreResult({
    required this.received,
    required this.messageRequest,
  });

  final bool received;
  final bool messageRequest;
}
