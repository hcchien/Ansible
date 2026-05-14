import 'dart:convert';
import 'dart:typed_data';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';

import 'messenger_crypto_bridge.dart';
import 'messenger_device_service.dart';
import 'messenger_relay_client.dart';

class MessengerSyncService {
  final MessengerRepository repository;
  final MessengerDeviceService deviceService;
  final MessengerRelayClient relayClient;
  final MessengerCryptoBridge crypto;
  final DidSigner didSigner;
  final DateTime Function() now;
  final String Function() idGenerator;

  MessengerSyncService({
    required this.repository,
    required this.deviceService,
    required this.relayClient,
    required this.crypto,
    required this.didSigner,
    DateTime Function()? now,
    String Function()? idGenerator,
  }) : now = now ?? (() => DateTime.now().toUtc()),
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

    final remoteDevice = recipientBundle.devices.first;
    final encrypted = await crypto.encryptInitialMessage(
      MessengerEncryptRequest(
        localDevice: _bundleFromRecord(localDevice),
        remoteBundle: _remoteBundleJson(recipientBundle, remoteDevice),
        plaintext: Uint8List.fromList(utf8.encode(text)),
      ),
    );

    final createdAt = now().toUtc();
    final messageId = idGenerator();
    final ciphertext = base64Encode(encrypted.ciphertext);
    final pending = MessengerMessageRecord(
      messageId: messageId,
      conversationId: recipientDid,
      direction: MessengerMessageDirection.outbound,
      status: MessengerMessageStatus.pending,
      plaintext: text,
      ciphertextType: encrypted.ciphertextType,
      ciphertext: ciphertext,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await repository.saveMessage(pending);
    await repository.saveSession(
      MessengerSessionRecord(
        localDeviceId: localDevice.deviceId,
        remoteDid: recipientDid,
        remoteDeviceId: remoteDevice.deviceId,
        sessionState: encrypted.updatedSessionState,
        updatedAt: createdAt,
      ),
    );

    await relayClient.sendMessage(
      messageId: messageId,
      senderDid: senderDid,
      senderDeviceId: localDevice.deviceId,
      recipientDid: recipientDid,
      recipientDeviceId: remoteDevice.deviceId,
      ciphertextType: encrypted.ciphertextType,
      ciphertext: ciphertext,
      protocolVersion: encrypted.protocolVersion,
      createdAt: createdAt,
      requestSignature: await _signJson({
        'message_id': messageId,
        'sender_did': senderDid,
        'sender_device_id': localDevice.deviceId,
        'recipient_did': recipientDid,
        'recipient_device_id': remoteDevice.deviceId,
        'ciphertext_type': encrypted.ciphertextType,
        'ciphertext': ciphertext,
        'protocol_version': encrypted.protocolVersion,
        'created_at': createdAt.toIso8601String(),
      }),
    );

    final sent = MessengerMessageRecord(
      messageId: pending.messageId,
      conversationId: pending.conversationId,
      direction: pending.direction,
      status: MessengerMessageStatus.sent,
      plaintext: pending.plaintext,
      ciphertextType: pending.ciphertextType,
      ciphertext: pending.ciphertext,
      createdAt: pending.createdAt,
      updatedAt: now().toUtc(),
    );
    await repository.saveMessage(sent);
    return sent;
  }

  Future<void> pullAndDecrypt({required String recipientDid}) async {
    final localDevice = await deviceService.ensurePublishedDevice(
      subjectDid: recipientDid,
      didSigner: didSigner,
    );
    final cursor = await repository.mailboxCursorFor(localDevice.deviceId);
    final mailbox = await relayClient.pullMailbox(
      recipientDeviceId: localDevice.deviceId,
      cursor: cursor,
    );

    for (final message in mailbox.messages) {
      await _decryptAndStore(localDevice, message);
    }

    final nextCursor = mailbox.nextCursor;
    if (nextCursor != null && nextCursor.isNotEmpty) {
      await repository.saveMailboxCursor(localDevice.deviceId, nextCursor);
    }
  }

  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) {
    return repository.messagesForConversation(conversationId);
  }

  Future<void> _decryptAndStore(
    MessengerDeviceRecord localDevice,
    MessengerMailboxMessage message,
  ) async {
    final receivedAt = message.createdAt ?? now().toUtc();
    try {
      final plaintext = await crypto.decryptInboundMessage(
        MessengerDecryptRequest(
          localDevice: _bundleFromRecord(localDevice),
          ciphertext: MessengerCiphertextEnvelope(
            protocolVersion: message.protocolVersion,
            ciphertextType: message.ciphertextType,
            ciphertext: base64Decode(message.ciphertext),
            updatedSessionState: '',
          ),
        ),
      );
      final updatedAt = now().toUtc();
      await repository.saveMessage(
        MessengerMessageRecord(
          messageId: message.messageId,
          conversationId: message.senderDid,
          direction: MessengerMessageDirection.inbound,
          status: MessengerMessageStatus.received,
          plaintext: utf8.decode(plaintext.body),
          ciphertextType: message.ciphertextType,
          ciphertext: message.ciphertext,
          createdAt: receivedAt,
          updatedAt: updatedAt,
        ),
      );
      await repository.saveSession(
        MessengerSessionRecord(
          localDeviceId: localDevice.deviceId,
          remoteDid: message.senderDid,
          remoteDeviceId: message.senderDeviceId,
          sessionState: plaintext.updatedSessionState,
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
    }
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
}
