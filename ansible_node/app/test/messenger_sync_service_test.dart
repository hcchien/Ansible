import 'dart:convert';
import 'dart:typed_data';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/messenger_crypto_bridge.dart';
import 'package:ansible_node/services/messenger_device_binding_verifier.dart';
import 'package:ansible_node/services/messenger_device_service.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:ansible_node/services/messenger_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends and receives encrypted text without relay plaintext', () async {
    final relay = _FakeMessengerRelayClient();
    final crypto = _FakeMessengerCryptoBridge();
    final aliceRepo = _InMemoryMessengerRepository();
    final bobRepo = _InMemoryMessengerRepository();
    final signer = _FakeDidSigner();
    final aliceSecretStore = _RecordingMessengerSecretStore();
    final bobSecretStore = _RecordingMessengerSecretStore();

    final aliceDevice = _deviceRecord(
      subjectDid: 'did:plc:alice',
      deviceId: 'msgdev_alice',
    );
    final bobDevice = _deviceRecord(
      subjectDid: 'did:plc:bob',
      deviceId: 'msgdev_bob',
    );
    await aliceRepo.upsertLocalDevice(aliceDevice);
    await bobRepo.upsertLocalDevice(bobDevice);

    final alice = MessengerSyncService(
      repository: aliceRepo,
      deviceService: MessengerDeviceService(
        repository: aliceRepo,
        crypto: crypto,
        relayClient: relay,
        secretStore: aliceSecretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: signer,
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: aliceSecretStore,
      now: () => DateTime.utc(2026, 5, 14),
      idGenerator: () => 'msg_alice_1',
    );
    final bob = MessengerSyncService(
      repository: bobRepo,
      deviceService: MessengerDeviceService(
        repository: bobRepo,
        crypto: crypto,
        relayClient: relay,
        secretStore: bobSecretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: signer,
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: bobSecretStore,
      now: () => DateTime.utc(2026, 5, 14),
      idGenerator: () => 'msg_bob_1',
    );

    relay.registerBundle(
      'did:plc:bob',
      const MessengerPreKeyBundleResponse(
        subjectDid: 'did:plc:bob',
        devices: [
          MessengerPreKeyBundleDevice(
            deviceId: 'msgdev_bob',
            messengerIdentityKey: 'bob_identity',
            signedPreKeyId: 42,
            signedPreKey: 'bob_signed_pre_key',
            signedPreKeySignature: 'bob_signature',
            oneTimePreKeyId: 1001,
            oneTimePreKey: 'bob_one_time_pre_key',
          ),
        ],
      ),
    );

    await alice.sendText(
      senderDid: 'did:plc:alice',
      recipientDid: 'did:plc:bob',
      text: 'hello bob',
    );

    expect(
      relay.acceptedCiphertexts.single.ciphertext,
      isNot(contains('hello bob')),
    );
    expect(relay.reservationRequests.single, {
      'subject_did': 'did:plc:bob',
      'sender_did': 'did:plc:alice',
      'sender_device_id': 'msgdev_alice',
      'request_id': 'msg_alice_1',
      'request_signature': 'dev-signature',
    });
    final rawAliceMessage = (await aliceRepo.messagesForConversation(
      'did:plc:bob',
    )).single;
    expect(rawAliceMessage.status, MessengerMessageStatus.sent);
    expect(rawAliceMessage.plaintext, startsWith('secure-storage:v1:'));
    expect(aliceSecretStore.values.values, contains('hello bob'));

    await bob.pullAndDecrypt(recipientDid: 'did:plc:bob');
    final rawBobMessage = (await bobRepo.messagesForConversation(
      'did:plc:alice',
    )).single;
    final messages = await bob.messagesForConversation('did:plc:alice');

    expect(rawBobMessage.plaintext, startsWith('secure-storage:v1:'));
    expect(messages.single.plaintext, 'hello bob');
    expect(messages.single.status, MessengerMessageStatus.received);
    expect(
      bobRepo.savedSessions.single.sessionState,
      startsWith('secure-storage:v1:'),
    );
    expect(
      bobSecretStore.values.values,
      containsAll(['hello bob', 'session:hello bob']),
    );
    expect(relay.ackedMessageIds, ['msg_alice_1']);
    expect(bobRepo.cursors['msgdev_bob'], 'cursor-2');

    await bob.pullAndDecrypt(recipientDid: 'did:plc:bob');
    expect(relay.observedCursors.last, 'cursor-2');
  });

  test('stores decrypt failures without acknowledging relay message', () async {
    final relay = _FakeMessengerRelayClient();
    final crypto = _FakeMessengerCryptoBridge(throwOnDecrypt: true);
    final repository = _InMemoryMessengerRepository();
    final secretStore = _RecordingMessengerSecretStore();
    final device = _deviceRecord(
      subjectDid: 'did:plc:bob',
      deviceId: 'msgdev_bob',
    );
    await repository.upsertLocalDevice(device);
    relay.queueMessage(
      MessengerMailboxMessage(
        messageId: 'msg_bad',
        senderDid: 'did:plc:alice',
        senderDeviceId: 'msgdev_alice',
        recipientDid: 'did:plc:bob',
        recipientDeviceId: 'msgdev_bob',
        ciphertextType: 'pre_key_signal_message',
        ciphertext: base64Encode(utf8.encode('cipher:recovered')),
        protocolVersion: 'signal-mvp-v1',
      ),
    );
    final service = MessengerSyncService(
      repository: repository,
      deviceService: MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
        secretStore: secretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: _FakeDidSigner(),
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: secretStore,
    );

    await service.pullAndDecrypt(recipientDid: 'did:plc:bob');

    final messages = await repository.messagesForConversation('did:plc:alice');
    expect(messages.single.status, MessengerMessageStatus.decryptFailed);
    expect(relay.ackedMessageIds, isEmpty);
    expect(repository.cursors['msgdev_bob'], isNull);

    crypto.throwOnDecrypt = false;
    await service.pullAndDecrypt(recipientDid: 'did:plc:bob');

    expect(relay.ackedMessageIds, ['msg_bad']);
    expect(repository.cursors['msgdev_bob'], 'cursor-2');
    expect(
      (await service.messagesForConversation('did:plc:alice')).single.plaintext,
      'recovered',
    );
  });

  test('retries acknowledgement before advancing the mailbox cursor', () async {
    final relay = _FakeMessengerRelayClient()..failNextAck = true;
    final crypto = _FakeMessengerCryptoBridge();
    final repository = _InMemoryMessengerRepository();
    final secretStore = _RecordingMessengerSecretStore();
    await repository.upsertLocalDevice(
      _deviceRecord(subjectDid: 'did:plc:bob', deviceId: 'msgdev_bob'),
    );
    relay.queueMessage(
      MessengerMailboxMessage(
        messageId: 'msg_ack_retry',
        senderDid: 'did:plc:alice',
        senderDeviceId: 'msgdev_alice',
        recipientDid: 'did:plc:bob',
        recipientDeviceId: 'msgdev_bob',
        ciphertextType: 'pre_key_signal_message',
        ciphertext: base64Encode(utf8.encode('cipher:only decrypt once')),
        protocolVersion: 'signal-mvp-v1',
      ),
    );
    final service = MessengerSyncService(
      repository: repository,
      deviceService: MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
        secretStore: secretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: _FakeDidSigner(),
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: secretStore,
    );

    await service.pullAndDecrypt(recipientDid: 'did:plc:bob');
    expect(repository.cursors['msgdev_bob'], isNull);
    expect(crypto.decryptCalls, 1);

    await service.pullAndDecrypt(recipientDid: 'did:plc:bob');
    expect(repository.cursors['msgdev_bob'], 'cursor-2');
    expect(relay.ackedMessageIds, ['msg_ack_retry']);
    expect(crypto.decryptCalls, 1);
  });

  test('fans one logical message out to every recipient device', () async {
    final relay = _FakeMessengerRelayClient();
    final crypto = _FakeMessengerCryptoBridge();
    final repository = _InMemoryMessengerRepository();
    final secretStore = _RecordingMessengerSecretStore();
    await repository.upsertLocalDevice(
      _deviceRecord(subjectDid: 'did:plc:alice', deviceId: 'msgdev_alice'),
    );
    relay.registerBundle(
      'did:plc:bob',
      const MessengerPreKeyBundleResponse(
        subjectDid: 'did:plc:bob',
        devices: [
          MessengerPreKeyBundleDevice(
            deviceId: 'msgdev_bob_phone',
            messengerIdentityKey: 'bob_phone_identity',
            signedPreKeyId: 10,
            signedPreKey: 'bob_phone_signed',
            signedPreKeySignature: 'bob_phone_signature',
            oneTimePreKeyId: 101,
            oneTimePreKey: 'bob_phone_once',
          ),
          MessengerPreKeyBundleDevice(
            deviceId: 'msgdev_bob_tablet',
            messengerIdentityKey: 'bob_tablet_identity',
            signedPreKeyId: 20,
            signedPreKey: 'bob_tablet_signed',
            signedPreKeySignature: 'bob_tablet_signature',
            oneTimePreKeyId: 201,
            oneTimePreKey: 'bob_tablet_once',
          ),
        ],
      ),
    );

    final service = MessengerSyncService(
      repository: repository,
      deviceService: MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
        secretStore: secretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: _FakeDidSigner(),
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: secretStore,
      now: () => DateTime.utc(2026, 9, 1),
      idGenerator: () => 'msg_multi_1',
    );

    final sent = await service.sendText(
      senderDid: 'did:plc:alice',
      recipientDid: 'did:plc:bob',
      text: 'hello every device',
    );

    expect(sent.messageId, 'msg_multi_1');
    expect(
      relay.acceptedCiphertexts.map((message) => message.messageId).toSet(),
      {'msg_multi_1.msgdev_bob_phone', 'msg_multi_1.msgdev_bob_tablet'},
    );
    expect(
      repository.savedSessions.map((session) => session.remoteDeviceId).toSet(),
      {'msgdev_bob_phone', 'msgdev_bob_tablet'},
    );
    expect((await repository.messagesForConversation('did:plc:bob')).length, 1);
  });

  test('retries a failed fanout as one durable atomic batch', () async {
    final relay = _FakeMessengerRelayClient()..failNextBatch = true;
    final crypto = _FakeMessengerCryptoBridge();
    final repository = _InMemoryMessengerRepository();
    final secretStore = _RecordingMessengerSecretStore();
    await repository.upsertLocalDevice(
      _deviceRecord(subjectDid: 'did:plc:alice', deviceId: 'msgdev_alice'),
    );
    relay.registerBundle(
      'did:plc:bob',
      const MessengerPreKeyBundleResponse(
        subjectDid: 'did:plc:bob',
        devices: [
          MessengerPreKeyBundleDevice(
            deviceId: 'msgdev_bob_phone',
            messengerIdentityKey: 'phone_identity',
            signedPreKeyId: 10,
            signedPreKey: 'phone_signed',
            signedPreKeySignature: 'phone_signature',
            oneTimePreKeyId: 101,
            oneTimePreKey: 'phone_once',
          ),
          MessengerPreKeyBundleDevice(
            deviceId: 'msgdev_bob_tablet',
            messengerIdentityKey: 'tablet_identity',
            signedPreKeyId: 20,
            signedPreKey: 'tablet_signed',
            signedPreKeySignature: 'tablet_signature',
            oneTimePreKeyId: 201,
            oneTimePreKey: 'tablet_once',
          ),
        ],
      ),
    );
    final service = MessengerSyncService(
      repository: repository,
      deviceService: MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
        secretStore: secretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: _FakeDidSigner(),
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: secretStore,
      idGenerator: () => 'msg_atomic_retry',
    );

    await expectLater(
      service.sendText(
        senderDid: 'did:plc:alice',
        recipientDid: 'did:plc:bob',
        text: 'retry me',
      ),
      throwsStateError,
    );
    expect(relay.acceptedCiphertexts, isEmpty);
    expect(
      repository.messages['msg_atomic_retry']!.status,
      MessengerMessageStatus.pending,
    );

    await service.ensureReady(subjectDid: 'did:plc:alice');
    expect(relay.batchAttempts, 2);
    expect(relay.acceptedCiphertexts, hasLength(2));
    expect(
      repository.messages['msg_atomic_retry']!.status,
      MessengerMessageStatus.sent,
    );
  });

  test(
    'fails closed when a known remote device changes identity key',
    () async {
      final relay = _FakeMessengerRelayClient();
      final crypto = _FakeMessengerCryptoBridge();
      final repository = _InMemoryMessengerRepository();
      final secretStore = _RecordingMessengerSecretStore();
      await repository.upsertLocalDevice(
        _deviceRecord(subjectDid: 'did:plc:alice', deviceId: 'msgdev_alice'),
      );
      await repository.upsertRemoteDevice(
        MessengerDeviceRecord(
          subjectDid: 'did:plc:bob',
          deviceId: 'msgdev_bob',
          identityKeyPublic: 'trusted_identity',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      );
      relay.registerBundle(
        'did:plc:bob',
        const MessengerPreKeyBundleResponse(
          subjectDid: 'did:plc:bob',
          devices: [
            MessengerPreKeyBundleDevice(
              deviceId: 'msgdev_bob',
              messengerIdentityKey: 'substituted_identity',
              signedPreKeyId: 10,
              signedPreKey: 'bob_signed',
              signedPreKeySignature: 'bob_signature',
              oneTimePreKeyId: 101,
              oneTimePreKey: 'bob_once',
            ),
          ],
        ),
      );
      final service = MessengerSyncService(
        repository: repository,
        deviceService: MessengerDeviceService(
          repository: repository,
          crypto: crypto,
          relayClient: relay,
          secretStore: secretStore,
        ),
        relayClient: relay,
        crypto: crypto,
        didSigner: _FakeDidSigner(),
        deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
        secretStore: secretStore,
      );

      await expectLater(
        service.sendText(
          senderDid: 'did:plc:alice',
          recipientDid: 'did:plc:bob',
          text: 'must not send',
        ),
        throwsA(isA<MessengerIdentityKeyChanged>()),
      );
      expect(relay.acceptedCiphertexts, isEmpty);
    },
  );

  test('marks unknown inbound senders as message requests', () async {
    final relay = _FakeMessengerRelayClient();
    final crypto = _FakeMessengerCryptoBridge();
    final repository = _InMemoryMessengerRepository();
    final contacts = _FakeContactRepository();
    final secretStore = _RecordingMessengerSecretStore();
    final device = _deviceRecord(
      subjectDid: 'did:plc:bob',
      deviceId: 'msgdev_bob',
    );
    await repository.upsertLocalDevice(device);
    relay.queueMessage(
      const MessengerMailboxMessage(
        messageId: 'msg_request',
        senderDid: 'did:plc:alice',
        senderDeviceId: 'msgdev_alice',
        recipientDid: 'did:plc:bob',
        recipientDeviceId: 'msgdev_bob',
        ciphertextType: 'pre_key_signal_message',
        ciphertext: 'aGVsbG8gYm9i',
        protocolVersion: 'signal-mvp-v1',
      ),
    );
    final service = MessengerSyncService(
      repository: repository,
      contactRepository: contacts,
      deviceService: MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
        secretStore: secretStore,
      ),
      relayClient: relay,
      crypto: crypto,
      didSigner: _FakeDidSigner(),
      deviceBindingVerifier: const _AllowMessengerDeviceBindingVerifier(),
      secretStore: secretStore,
      now: () => DateTime.utc(2026, 5, 15),
    );

    final result = await service.pullAndDecrypt(recipientDid: 'did:plc:bob');

    expect(result.receivedMessages, 1);
    expect(result.messageRequests, 1);
    final contact = await contacts.contactForDid('did:plc:alice');
    expect(contact!.relationship, ContactRelationship.invite);
    expect(contact.source, 'message_request');
  });
}

MessengerDeviceRecord _deviceRecord({
  required String subjectDid,
  required String deviceId,
}) {
  return MessengerDeviceRecord(
    subjectDid: subjectDid,
    deviceId: deviceId,
    identityKeyPublic: '$deviceId.identity',
    identityKeyPrivateRef: 'secure:$deviceId.identity',
    isLocal: true,
    signedPreKeyId: 42,
    signedPreKeyPublic: '$deviceId.signed',
    signedPreKeyPrivateRef: 'secure:$deviceId.signed',
    signedPreKeySignature: '$deviceId.signature',
    createdAt: DateTime.utc(2026, 5, 14),
  );
}

class _FakeMessengerCryptoBridge implements MessengerCryptoBridge {
  _FakeMessengerCryptoBridge({this.throwOnDecrypt = false});

  bool throwOnDecrypt;
  var decryptCalls = 0;

  @override
  Future<MessengerDeviceBundle> createDevice(String subjectDid) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MessengerCryptoPreKey>> generatePreKeys(
    MessengerDeviceBundle device,
    int count,
  ) async {
    return const [];
  }

  @override
  Future<MessengerCiphertextEnvelope> encryptInitialMessage(
    MessengerEncryptRequest request,
  ) async {
    final plaintext = utf8.decode(request.plaintext);
    return MessengerCiphertextEnvelope(
      protocolVersion: 'signal-mvp-v1',
      ciphertextType: 'pre_key_signal_message',
      ciphertext: Uint8List.fromList(utf8.encode('cipher:$plaintext')),
      updatedSessionState: 'session:$plaintext',
    );
  }

  @override
  Future<MessengerPlaintextEnvelope> decryptInboundMessage(
    MessengerDecryptRequest request,
  ) async {
    decryptCalls += 1;
    if (throwOnDecrypt) {
      throw StateError('decrypt failed');
    }
    final ciphertext = utf8.decode(request.ciphertext.ciphertext);
    final plaintext = ciphertext.replaceFirst('cipher:', '');
    return MessengerPlaintextEnvelope(
      body: Uint8List.fromList(utf8.encode(plaintext)),
      updatedSessionState: 'session:$plaintext',
    );
  }
}

class _FakeMessengerRelayClient extends MessengerRelayClient {
  _FakeMessengerRelayClient() : super(baseUrl: 'http://unused.local');

  final bundles = <String, MessengerPreKeyBundleResponse>{};
  final acceptedCiphertexts = <_AcceptedCiphertext>[];
  final reservationRequests = <Map<String, String>>[];
  final queuedMessages = <MessengerMailboxMessage>[];
  final ackedMessageIds = <String>[];
  final observedCursors = <String?>[];
  var failNextBatch = false;
  var failNextAck = false;
  var batchAttempts = 0;

  void registerBundle(String subjectDid, MessengerPreKeyBundleResponse bundle) {
    bundles[subjectDid] = bundle;
  }

  void queueMessage(MessengerMailboxMessage message) {
    queuedMessages.add(message);
  }

  @override
  Future<MessengerPreKeyBundleResponse> fetchPreKeyBundle({
    required String subjectDid,
    required String senderDid,
    required String senderDeviceId,
    required String requestId,
    required String requestSignature,
  }) async {
    reservationRequests.add({
      'subject_did': subjectDid,
      'sender_did': senderDid,
      'sender_device_id': senderDeviceId,
      'request_id': requestId,
      'request_signature': requestSignature,
    });
    final bundle = bundles[subjectDid];
    if (bundle == null) throw StateError('missing bundle');
    return bundle;
  }

  @override
  Future<void> sendMessage({
    required String messageId,
    required String senderDid,
    required String senderDeviceId,
    required String recipientDid,
    required String recipientDeviceId,
    required String ciphertextType,
    required String ciphertext,
    required String protocolVersion,
    required DateTime createdAt,
    required String requestSignature,
  }) async {
    acceptedCiphertexts.add(
      _AcceptedCiphertext(messageId: messageId, ciphertext: ciphertext),
    );
    queuedMessages.add(
      MessengerMailboxMessage(
        messageId: messageId,
        senderDid: senderDid,
        senderDeviceId: senderDeviceId,
        recipientDid: recipientDid,
        recipientDeviceId: recipientDeviceId,
        ciphertextType: ciphertextType,
        ciphertext: ciphertext,
        protocolVersion: protocolVersion,
        createdAt: createdAt,
      ),
    );
  }

  @override
  Future<void> sendMessages({
    required List<Map<String, Object?>> messages,
    required String requestSignature,
  }) async {
    batchAttempts += 1;
    if (failNextBatch) {
      failNextBatch = false;
      throw StateError('batch failed before commit');
    }
    for (final message in messages) {
      await sendMessage(
        messageId: message['message_id']! as String,
        senderDid: message['sender_did']! as String,
        senderDeviceId: message['sender_device_id']! as String,
        recipientDid: message['recipient_did']! as String,
        recipientDeviceId: message['recipient_device_id']! as String,
        ciphertextType: message['ciphertext_type']! as String,
        ciphertext: message['ciphertext']! as String,
        protocolVersion: message['protocol_version']! as String,
        createdAt: DateTime.parse(message['created_at']! as String),
        requestSignature: requestSignature,
      );
    }
  }

  @override
  Future<MessengerMailboxResponse> pullMailbox({
    required String recipientDid,
    required String recipientDeviceId,
    required String requestSignature,
    String? cursor,
  }) async {
    observedCursors.add(cursor);
    return MessengerMailboxResponse(
      messages: queuedMessages
          .where(
            (message) =>
                message.recipientDid == recipientDid &&
                message.recipientDeviceId == recipientDeviceId,
          )
          .toList(growable: false),
      nextCursor: 'cursor-2',
    );
  }

  @override
  Future<void> ackMessage({
    required String messageId,
    required String recipientDid,
    required String recipientDeviceId,
    required String requestSignature,
  }) async {
    if (failNextAck) {
      failNextAck = false;
      throw StateError('ack failed');
    }
    ackedMessageIds.add(messageId);
    queuedMessages.removeWhere((message) => message.messageId == messageId);
  }
}

class _AcceptedCiphertext {
  final String messageId;
  final String ciphertext;

  const _AcceptedCiphertext({
    required this.messageId,
    required this.ciphertext,
  });
}

class _FakeDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return const Ed25519Signature('dev-signature');
  }
}

class _RecordingMessengerSecretStore implements MessengerSecretStore {
  final values = <String, String>{};

  @override
  bool isSecretReference(String value) {
    return value.startsWith('secure-storage:v1:') ||
        value.startsWith('secure:');
  }

  @override
  Future<String> putSecret({
    required String namespace,
    required String secretId,
    required String secret,
  }) async {
    final ref = 'secure-storage:v1:$namespace:$secretId';
    values[ref] = secret;
    return ref;
  }

  @override
  Future<String> resolveSecret(String value) async => values[value] ?? value;
}

class _InMemoryMessengerRepository
    implements
        MessengerRepository,
        MessengerRemoteDeviceTrustRepository,
        MessengerMessageLookupRepository,
        MessengerPendingOutboxRepository {
  final devices = <MessengerDeviceRecord>[];
  final messages = <String, MessengerMessageRecord>{};
  final savedSessions = <MessengerSessionRecord>[];
  final preKeys = <MessengerPreKeyRecord>[];
  final cursors = <String, String>{};

  @override
  Future<MessengerDeviceRecord?> localDeviceForSubject(
    String subjectDid,
  ) async {
    return devices
        .where((device) => device.subjectDid == subjectDid && device.isLocal)
        .firstOrNull;
  }

  @override
  Future<void> upsertLocalDevice(MessengerDeviceRecord device) async {
    devices.removeWhere((item) => item.deviceId == device.deviceId);
    devices.add(device.copyWith(isLocal: true));
  }

  @override
  Future<void> upsertRemoteDevice(MessengerDeviceRecord device) async {
    devices.removeWhere((item) => item.deviceId == device.deviceId);
    devices.add(device.copyWith(isLocal: false));
  }

  @override
  Future<MessengerDeviceRecord?> deviceById(String deviceId) async =>
      devices.where((device) => device.deviceId == deviceId).firstOrNull;

  @override
  Future<void> savePreKeys(List<MessengerPreKeyRecord> records) async {
    preKeys.addAll(records);
  }

  @override
  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(
    String deviceId,
  ) async {
    return preKeys
        .where(
          (preKey) => preKey.deviceId == deviceId && preKey.publishedAt == null,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) async {}

  @override
  Future<void> saveSession(MessengerSessionRecord session) async {
    savedSessions.add(session);
  }

  @override
  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  ) async {
    return savedSessions
        .where(
          (session) =>
              session.localDeviceId == localDeviceId &&
              session.remoteDeviceId == remoteDeviceId,
        )
        .lastOrNull;
  }

  @override
  Future<List<MessengerConversationRecord>> conversationList() async {
    final conversationIds = messages.values
        .map((message) => message.conversationId)
        .toSet();
    return [
      for (final conversationId in conversationIds)
        MessengerConversationRecord(
          conversationId: conversationId,
          peerDid: conversationId,
          createdAt: messages.values
              .where((message) => message.conversationId == conversationId)
              .map((message) => message.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          updatedAt: DateTime.utc(2026, 5, 14),
          lastMessageAt: messages.values
              .where((message) => message.conversationId == conversationId)
              .map((message) => message.createdAt)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
    ];
  }

  @override
  Future<void> saveMessage(MessengerMessageRecord message) async {
    messages[message.messageId] = message;
  }

  @override
  Future<MessengerMessageRecord?> messageById(String messageId) async =>
      messages[messageId];

  @override
  Future<List<MessengerMessageRecord>> pendingOutboundMessages() async =>
      messages.values
          .where(
            (message) =>
                message.direction == MessengerMessageDirection.outbound &&
                message.status == MessengerMessageStatus.pending,
          )
          .toList(growable: false);

  @override
  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) async {
    return messages.values
        .where((message) => message.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<String?> mailboxCursorFor(String localDeviceId) async {
    return cursors[localDeviceId];
  }

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) async {
    cursors[localDeviceId] = cursor;
  }
}

class _AllowMessengerDeviceBindingVerifier
    implements MessengerDeviceBindingVerifier {
  const _AllowMessengerDeviceBindingVerifier();

  @override
  Future<void> verify({
    required String subjectDid,
    required MessengerPreKeyBundleDevice device,
  }) async {}
}

class _FakeContactRepository implements ContactRepository {
  final contacts = <String, ContactRecord>{};

  @override
  Future<ContactRecord?> contactForDid(String subjectDid) async {
    return contacts[subjectDid];
  }

  @override
  Future<ContactRecord?> contactForHandle(String handle) async {
    return contacts.values
        .where((contact) => contact.handle == handle)
        .firstOrNull;
  }

  @override
  Future<List<ContactRecord>> listContacts() async {
    return contacts.values.toList(growable: false);
  }

  @override
  Future<ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  }) async {
    final contact = ContactRecord(
      subjectDid: resolvedDid,
      handle: handle,
      source: 'manual',
      trustState: ContactTrustState.known,
      createdAt: resolvedAt,
      updatedAt: resolvedAt,
      lastResolvedAt: resolvedAt,
    );
    await upsertContact(contact);
    return contact;
  }

  @override
  Future<void> upsertContact(ContactRecord contact) async {
    contacts[contact.subjectDid] = contact;
  }
}
