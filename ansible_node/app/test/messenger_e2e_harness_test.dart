import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/messenger_crypto_bridge.dart';
import 'package:ansible_node/services/messenger_device_service.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:ansible_node/services/messenger_sync_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Alice sends encrypted message to Bob through relay mailbox', () async {
    final harness = MessengerE2eHarness.withInMemoryRelay();
    await harness.createIdentity('alice');
    await harness.createIdentity('bob');
    await harness.publishMessengerDevice('alice');
    await harness.publishMessengerDevice('bob');

    await harness.sendText(from: 'alice', to: 'bob', text: 'hello bob');

    expect(harness.relayCiphertexts.single, isNot(contains('hello bob')));

    await harness.pullAndDecrypt('bob');
    expect(await harness.messagesFor('bob', 'alice'), ['hello bob']);
    expect(harness.ackedMessageIds, hasLength(1));
  });
}

class MessengerE2eHarness {
  MessengerE2eHarness.withInMemoryRelay()
    : _relay = _InMemoryRelayClient(),
      _crypto = RustMessengerCryptoBridge();

  final _InMemoryRelayClient _relay;
  final MessengerCryptoBridge _crypto;
  final _signer = _HarnessDidSigner();
  final _repositories = <String, _InMemoryMessengerRepository>{};
  final _services = <String, MessengerSyncService>{};
  final _dids = <String, String>{};
  var _nextMessageId = 0;

  List<String> get relayCiphertexts => _relay.ciphertexts;

  List<String> get ackedMessageIds => _relay.ackedMessageIds;

  Future<void> createIdentity(String alias) async {
    final did = 'did:plc:$alias';
    _dids[alias] = did;
    final repository = _InMemoryMessengerRepository();
    _repositories[alias] = repository;
    _services[alias] = MessengerSyncService(
      repository: repository,
      deviceService: MessengerDeviceService(
        repository: repository,
        crypto: _crypto,
        relayClient: _relay,
      ),
      relayClient: _relay,
      crypto: _crypto,
      didSigner: _signer,
      now: () => DateTime.utc(2026, 5, 14, 10, _nextMessageId),
      idGenerator: () => 'msg_${++_nextMessageId}',
    );
  }

  Future<void> publishMessengerDevice(String alias) async {
    await _service(alias).ensureReady(subjectDid: _did(alias));
  }

  Future<void> sendText({
    required String from,
    required String to,
    required String text,
  }) {
    return _service(
      from,
    ).sendText(senderDid: _did(from), recipientDid: _did(to), text: text);
  }

  Future<void> pullAndDecrypt(String alias) {
    return _service(alias).pullAndDecrypt(recipientDid: _did(alias));
  }

  Future<List<String?>> messagesFor(String ownerAlias, String peerAlias) async {
    final records = await _service(
      ownerAlias,
    ).messagesForConversation(_did(peerAlias));
    return records.map((message) => message.plaintext).toList(growable: false);
  }

  MessengerSyncService _service(String alias) {
    final service = _services[alias];
    if (service == null) throw StateError('Missing service for $alias');
    return service;
  }

  String _did(String alias) {
    final did = _dids[alias];
    if (did == null) throw StateError('Missing DID for $alias');
    return did;
  }
}

class _InMemoryRelayClient extends MessengerRelayClient {
  _InMemoryRelayClient() : super(baseUrl: 'http://unused.local');

  final _devices = <String, _PublishedDevice>{};
  final _preKeys = <String, List<Map<String, Object?>>>{};
  final _mailbox = <MessengerMailboxMessage>[];
  final ciphertexts = <String>[];
  final ackedMessageIds = <String>[];

  @override
  Future<void> publishDevice({
    required String subjectDid,
    required String deviceId,
    required Map<String, Object?> bundle,
    required Map<String, Object?> binding,
    required String bindingSignature,
  }) async {
    _devices[subjectDid] = _PublishedDevice(
      subjectDid: subjectDid,
      deviceId: deviceId,
      bundle: bundle,
      binding: binding,
      bindingSignature: bindingSignature,
    );
  }

  @override
  Future<void> publishPreKeys({
    required String subjectDid,
    required String deviceId,
    required List<Map<String, Object?>> preKeys,
    required String requestSignature,
  }) async {
    _preKeys[subjectDid] = [...?_preKeys[subjectDid], ...preKeys];
  }

  @override
  Future<MessengerPreKeyBundleResponse> fetchPreKeyBundle(
    String subjectDid,
  ) async {
    final device = _devices[subjectDid];
    final preKey = _preKeys[subjectDid]?.firstOrNull;
    if (device == null || preKey == null) {
      throw StateError('missing pre-key bundle for $subjectDid');
    }
    return MessengerPreKeyBundleResponse(
      subjectDid: subjectDid,
      devices: [
        MessengerPreKeyBundleDevice(
          deviceId: device.deviceId,
          messengerIdentityKey:
              device.bundle['messenger_identity_key']! as String,
          signedPreKeyId: device.bundle['signed_pre_key_id']! as int,
          signedPreKey: device.bundle['signed_pre_key']! as String,
          signedPreKeySignature:
              device.bundle['signed_pre_key_signature']! as String,
          oneTimePreKeyId: preKey['pre_key_id']! as int,
          oneTimePreKey: preKey['pre_key']! as String,
          binding: device.binding,
          bindingSignature: device.bindingSignature,
        ),
      ],
    );
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
    ciphertexts.add(ciphertext);
    _mailbox.add(
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
  Future<MessengerMailboxResponse> pullMailbox({
    required String recipientDeviceId,
    String? cursor,
  }) async {
    return MessengerMailboxResponse(
      messages: _mailbox
          .where((message) => message.recipientDeviceId == recipientDeviceId)
          .toList(growable: false),
      nextCursor: 'cursor-${_mailbox.length}',
    );
  }

  @override
  Future<void> ackMessage({
    required String messageId,
    required String recipientDid,
    required String recipientDeviceId,
    required String requestSignature,
  }) async {
    ackedMessageIds.add(messageId);
    _mailbox.removeWhere((message) => message.messageId == messageId);
  }
}

class _PublishedDevice {
  final String subjectDid;
  final String deviceId;
  final Map<String, Object?> bundle;
  final Map<String, Object?> binding;
  final String bindingSignature;

  const _PublishedDevice({
    required this.subjectDid,
    required this.deviceId,
    required this.bundle,
    required this.binding,
    required this.bindingSignature,
  });
}

class _HarnessDidSigner implements DidSigner {
  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    return const Ed25519Signature('dev-signature');
  }
}

class _InMemoryMessengerRepository implements MessengerRepository {
  final _devices = <MessengerDeviceRecord>[];
  final _preKeys = <String, MessengerPreKeyRecord>{};
  final _sessions = <MessengerSessionRecord>[];
  final _messages = <String, MessengerMessageRecord>{};
  final _cursors = <String, String>{};

  @override
  Future<List<MessengerConversationRecord>> conversationList() async {
    final ids = _messages.values
        .map((message) => message.conversationId)
        .toSet();
    return [
      for (final id in ids)
        MessengerConversationRecord(
          conversationId: id,
          peerDid: id,
          createdAt: _messages.values
              .where((message) => message.conversationId == id)
              .map((message) => message.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          updatedAt: DateTime.utc(2026, 5, 14),
          lastMessageAt: _messages.values
              .where((message) => message.conversationId == id)
              .map((message) => message.createdAt)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
    ];
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
  Future<void> upsertLocalDevice(MessengerDeviceRecord device) async {
    _devices.removeWhere((item) => item.deviceId == device.deviceId);
    _devices.add(device.copyWith(isLocal: true));
  }

  @override
  Future<void> upsertRemoteDevice(MessengerDeviceRecord device) async {
    _devices.removeWhere((item) => item.deviceId == device.deviceId);
    _devices.add(device.copyWith(isLocal: false));
  }

  @override
  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys) async {
    for (final preKey in preKeys) {
      _preKeys['${preKey.deviceId}:${preKey.preKeyId}'] = preKey;
    }
  }

  @override
  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(
    String deviceId,
  ) async {
    return _preKeys.values
        .where(
          (preKey) =>
              preKey.deviceId == deviceId &&
              preKey.publishedAt == null &&
              preKey.consumedAt == null,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) async {
    final key = '$deviceId:$preKeyId';
    final existing = _preKeys[key];
    if (existing == null) return;
    _preKeys[key] = MessengerPreKeyRecord(
      deviceId: existing.deviceId,
      preKeyId: existing.preKeyId,
      publicKey: existing.publicKey,
      privateKeyRef: existing.privateKeyRef,
      createdAt: existing.createdAt,
      publishedAt: DateTime.utc(2026, 5, 14),
      consumedAt: existing.consumedAt,
    );
  }

  @override
  Future<void> saveSession(MessengerSessionRecord session) async {
    _sessions.add(session);
  }

  @override
  Future<MessengerSessionRecord?> sessionFor(
    String localDeviceId,
    String remoteDeviceId,
  ) async {
    return _sessions
        .where(
          (session) =>
              session.localDeviceId == localDeviceId &&
              session.remoteDeviceId == remoteDeviceId,
        )
        .lastOrNull;
  }

  @override
  Future<void> saveMessage(MessengerMessageRecord message) async {
    _messages[message.messageId] = message;
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
  Future<String?> mailboxCursorFor(String localDeviceId) async {
    return _cursors[localDeviceId];
  }

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) async {
    _cursors[localDeviceId] = cursor;
  }
}
