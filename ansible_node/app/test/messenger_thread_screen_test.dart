import 'dart:convert';
import 'dart:typed_data';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/screens/messenger_thread_screen.dart';
import 'package:ansible_node/services/messenger_crypto_bridge.dart';
import 'package:ansible_node/services/messenger_device_service.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:ansible_node/services/messenger_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('thread renders inbound outbound and decrypt-failed rows', (
    tester,
  ) async {
    final service = _serviceWith(
      repository: _InMemoryMessengerRepository(
        messages: [
          MessengerMessageRecord(
            messageId: 'msg_in',
            conversationId: 'did:plc:bob',
            direction: MessengerMessageDirection.inbound,
            status: MessengerMessageStatus.received,
            plaintext: 'hello alice',
            createdAt: DateTime.utc(2026, 5, 14, 9),
          ),
          MessengerMessageRecord(
            messageId: 'msg_out',
            conversationId: 'did:plc:bob',
            direction: MessengerMessageDirection.outbound,
            status: MessengerMessageStatus.sent,
            plaintext: 'hello bob',
            createdAt: DateTime.utc(2026, 5, 14, 9, 1),
          ),
          MessengerMessageRecord(
            messageId: 'msg_bad',
            conversationId: 'did:plc:bob',
            direction: MessengerMessageDirection.inbound,
            status: MessengerMessageStatus.decryptFailed,
            ciphertextType: 'pre_key_signal_message',
            ciphertext: 'bad',
            createdAt: DateTime.utc(2026, 5, 14, 9, 2),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MessengerThreadScreen(
          conversationId: 'did:plc:bob',
          messengerService: service,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('hello alice'), findsOneWidget);
    expect(find.text('hello bob'), findsOneWidget);
    expect(find.text('無法解密這則訊息'), findsOneWidget);
  });

  testWidgets('composer sends non-empty text through messenger service', (
    tester,
  ) async {
    final repository = _InMemoryMessengerRepository(
      localDevices: [_deviceRecord('did:plc:alice', 'msgdev_alice')],
    );
    final relay = _FakeMessengerRelayClient()
      ..registerBundle(
        'did:plc:bob',
        const MessengerPreKeyBundleResponse(
          subjectDid: 'did:plc:bob',
          devices: [
            MessengerPreKeyBundleDevice(
              deviceId: 'msgdev_bob',
              messengerIdentityKey: 'bob.identity',
              signedPreKeyId: 1,
              signedPreKey: 'bob.signed',
              signedPreKeySignature: 'bob.signature',
              oneTimePreKeyId: 7,
              oneTimePreKey: 'bob.one-time',
            ),
          ],
        ),
      );
    final service = _serviceWith(repository: repository, relay: relay);

    await tester.pumpWidget(
      MaterialApp(
        home: MessengerThreadScreen(
          conversationId: 'did:plc:bob',
          senderDid: 'did:plc:alice',
          messengerService: service,
        ),
      ),
    );
    await tester.pump();

    final sendButton = find.byKey(const ValueKey('messenger-send-button'));
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('messenger-composer')),
      'hi bob',
    );
    await tester.pump();
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);

    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(relay.acceptedPlaintexts, ['hi bob']);
    expect(find.text('hi bob'), findsOneWidget);
  });
}

MessengerSyncService _serviceWith({
  required _InMemoryMessengerRepository repository,
  _FakeMessengerRelayClient? relay,
}) {
  final crypto = _FakeMessengerCryptoBridge();
  final relayClient = relay ?? _FakeMessengerRelayClient();
  return MessengerSyncService(
    repository: repository,
    deviceService: MessengerDeviceService(
      repository: repository,
      crypto: crypto,
      relayClient: relayClient,
    ),
    relayClient: relayClient,
    crypto: crypto,
    didSigner: _FakeDidSigner(),
    now: () => DateTime.utc(2026, 5, 14, 9, 3),
    idGenerator: () => 'msg_thread_1',
  );
}

MessengerDeviceRecord _deviceRecord(String subjectDid, String deviceId) {
  return MessengerDeviceRecord(
    subjectDid: subjectDid,
    deviceId: deviceId,
    identityKeyPublic: '$deviceId.identity',
    identityKeyPrivateRef: 'secure:$deviceId.identity',
    isLocal: true,
    signedPreKeyId: 1,
    signedPreKeyPublic: '$deviceId.signed',
    signedPreKeyPrivateRef: 'secure:$deviceId.signed',
    signedPreKeySignature: '$deviceId.signature',
    createdAt: DateTime.utc(2026, 5, 14),
  );
}

class _FakeMessengerCryptoBridge implements MessengerCryptoBridge {
  @override
  Future<MessengerDeviceBundle> createDevice(String subjectDid) async {
    return MessengerDeviceBundle(
      subjectDid: subjectDid,
      deviceId: 'msgdev_${subjectDid.split(':').last}',
      identityKeyPublic: '$subjectDid.identity',
      identityKeyPrivateRef: 'secure:$subjectDid.identity',
      signedPreKeyId: 1,
      signedPreKeyPublic: '$subjectDid.signed',
      signedPreKeyPrivateRef: 'secure:$subjectDid.signed',
      signedPreKeySignature: '$subjectDid.signature',
    );
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
  final acceptedPlaintexts = <String>[];

  void registerBundle(String subjectDid, MessengerPreKeyBundleResponse bundle) {
    bundles[subjectDid] = bundle;
  }

  @override
  Future<MessengerPreKeyBundleResponse> fetchPreKeyBundle(
    String subjectDid,
  ) async {
    return bundles[subjectDid]!;
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
    acceptedPlaintexts.add(
      utf8.decode(base64Decode(ciphertext)).replaceFirst('cipher:', ''),
    );
  }
}

class _FakeDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return const Ed25519Signature('dev-signature');
  }
}

class _InMemoryMessengerRepository implements MessengerRepository {
  _InMemoryMessengerRepository({
    List<MessengerMessageRecord>? messages,
    List<MessengerDeviceRecord>? localDevices,
  }) : _messages = {
         for (final message in messages ?? <MessengerMessageRecord>[])
           message.messageId: message,
       },
       _devices = localDevices ?? const [];

  final Map<String, MessengerMessageRecord> _messages;
  final List<MessengerDeviceRecord> _devices;

  @override
  Future<List<MessengerConversationRecord>> conversationList() async {
    return const [];
  }

  @override
  Future<MessengerDeviceRecord?> localDeviceForSubject(
    String subjectDid,
  ) async {
    return _devices
        .where((device) => device.subjectDid == subjectDid && device.isLocal)
        .firstOrNull;
  }

  @override
  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) async {
    return _messages.values
        .where((message) => message.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<void> saveMessage(MessengerMessageRecord message) async {
    _messages[message.messageId] = message;
  }

  @override
  Future<String?> mailboxCursorFor(String localDeviceId) async {
    return null;
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) async {}

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) async {}

  @override
  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys) async {}

  @override
  Future<void> saveSession(MessengerSessionRecord session) async {}

  @override
  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  ) async {
    return null;
  }

  @override
  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(
    String deviceId,
  ) async {
    return const [];
  }

  @override
  Future<void> upsertLocalDevice(MessengerDeviceRecord device) async {}

  @override
  Future<void> upsertRemoteDevice(MessengerDeviceRecord device) async {}
}
