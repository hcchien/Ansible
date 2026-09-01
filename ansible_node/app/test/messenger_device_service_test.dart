import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_node/services/messenger_crypto_bridge.dart';
import 'package:ansible_node/services/messenger_device_service.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('secure storage secret references support colon in namespace', () async {
    const store = SecureStorageMessengerSecretStore();

    final reference = await store.putSecret(
      namespace: 'message.msg:remote',
      secretId: 'plaintext',
      secret: 'hello',
    );

    expect(await store.resolveSecret(reference), 'hello');
  });

  test(
    'creates, stores, signs, and publishes a local messenger device',
    () async {
      final repository = _FakeMessengerRepository();
      final crypto = _FakeMessengerCryptoBridge();
      final relay = _RecordingMessengerRelayClient();
      final signer = _RecordingDidSigner();
      final service = MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
      );

      final device = await service.ensurePublishedDevice(
        subjectDid: 'did:plc:alice',
        didSigner: signer,
      );

      expect(device.deviceId, 'msgdev_alice');
      expect(
        repository.savedDevices.single.identityKeyPrivateRef,
        'secure:identity',
      );
      expect(repository.savedPreKeys, hasLength(20));
      expect(relay.publishedDevices.single.subjectDid, 'did:plc:alice');
      expect(
        relay.publishedDevices.single.bundle.containsKey(
          'identity_key_private',
        ),
        isFalse,
      );
      expect(
        relay.publishedDevices.single.bundle.containsKey(
          'signed_pre_key_private',
        ),
        isFalse,
      );
      expect(relay.publishedPreKeys.single.preKeys, hasLength(20));
      expect(
        signer.messages.any((message) => message.contains('msgdev_alice')),
        isTrue,
      );
    },
  );

  test('moves generated messenger private keys into secret storage', () async {
    final repository = _FakeMessengerRepository();
    final relay = _RecordingMessengerRelayClient();
    final secretStore = _RecordingMessengerSecretStore();
    final service = MessengerDeviceService(
      repository: repository,
      crypto: _RawKeyMessengerCryptoBridge(),
      relayClient: relay,
      secretStore: secretStore,
    );

    await service.ensurePublishedDevice(
      subjectDid: 'did:plc:alice',
      didSigner: _RecordingDidSigner(),
    );

    final device = repository.savedDevices.single;
    expect(device.identityKeyPrivateRef, startsWith('secure-storage:v1:'));
    expect(device.signedPreKeyPrivateRef, startsWith('secure-storage:v1:'));
    expect(
      device.identityKeyPrivateRef,
      isNot(contains('raw_identity_private')),
    );
    expect(
      repository.savedPreKeys.map((preKey) => preKey.privateKeyRef),
      everyElement(startsWith('secure-storage:v1:')),
    );
    expect(
      secretStore.values.values,
      containsAll([
        'raw_identity_private',
        'raw_signed_pre_key_private',
        'raw_pre_key_private_0',
      ]),
    );
  });

  test(
    'reuses existing local device and only replenishes low pre-key stock',
    () async {
      final existing = MessengerDeviceRecord(
        subjectDid: 'did:plc:alice',
        deviceId: 'msgdev_existing',
        identityKeyPublic: 'existing_identity',
        identityKeyPrivateRef: 'secure:existing',
        isLocal: true,
        signedPreKeyId: 7,
        signedPreKeyPublic: 'existing_signed_pre_key',
        signedPreKeyPrivateRef: 'secure:existing_signed',
        signedPreKeySignature: 'existing_signature',
        createdAt: DateTime.utc(2026, 5, 14),
      );
      final repository = _FakeMessengerRepository(
        existingDevice: existing,
        unpublishedPreKeys: [
          for (var i = 0; i < 4; i += 1)
            MessengerPreKeyRecord(
              deviceId: 'msgdev_existing',
              preKeyId: i,
              publicKey: 'existing_pre_$i',
              createdAt: DateTime.utc(2026, 5, 14),
            ),
        ],
      );
      final crypto = _FakeMessengerCryptoBridge();
      final relay = _RecordingMessengerRelayClient();
      final service = MessengerDeviceService(
        repository: repository,
        crypto: crypto,
        relayClient: relay,
      );

      final device = await service.ensurePublishedDevice(
        subjectDid: 'did:plc:alice',
        didSigner: _RecordingDidSigner(),
      );

      expect(device.deviceId, 'msgdev_existing');
      expect(crypto.createdDeviceCount, 0);
      expect(relay.publishedDevices, isEmpty);
      expect(relay.publishedPreKeys, hasLength(2));
      expect(relay.publishedPreKeys.first.deviceId, 'msgdev_existing');
      expect(relay.publishedPreKeys.first.preKeys, hasLength(4));
      expect(relay.publishedPreKeys.last.preKeys, hasLength(20));
      expect(repository.savedPreKeys, hasLength(20));
    },
  );

  test('migrates existing raw device and pre-key secrets', () async {
    final existing = MessengerDeviceRecord(
      subjectDid: 'did:plc:alice',
      deviceId: 'msgdev_existing',
      identityKeyPublic: 'existing_identity',
      identityKeyPrivateRef: 'raw_existing_identity',
      isLocal: true,
      signedPreKeyId: 7,
      signedPreKeyPublic: 'existing_signed_pre_key',
      signedPreKeyPrivateRef: 'raw_existing_signed',
      signedPreKeySignature: 'existing_signature',
      createdAt: DateTime.utc(2026, 5, 14),
    );
    final repository = _FakeMessengerRepository(
      existingDevice: existing,
      unpublishedPreKeys: [
        for (
          var i = 0;
          i < MessengerDeviceService.minUnpublishedPreKeys;
          i += 1
        )
          MessengerPreKeyRecord(
            deviceId: 'msgdev_existing',
            preKeyId: i,
            publicKey: 'existing_pre_$i',
            privateKeyRef: 'raw_existing_pre_$i',
            createdAt: DateTime.utc(2026, 5, 14),
          ),
      ],
    );
    final secretStore = _RecordingMessengerSecretStore();
    final service = MessengerDeviceService(
      repository: repository,
      crypto: _FakeMessengerCryptoBridge(),
      relayClient: _RecordingMessengerRelayClient(),
      secretStore: secretStore,
    );

    final device = await service.ensurePublishedDevice(
      subjectDid: 'did:plc:alice',
      didSigner: _RecordingDidSigner(),
    );

    expect(device.identityKeyPrivateRef, startsWith('secure-storage:v1:'));
    expect(device.signedPreKeyPrivateRef, startsWith('secure-storage:v1:'));
    expect(
      repository.savedDevices.single.identityKeyPrivateRef,
      device.identityKeyPrivateRef,
    );
    expect(
      repository.savedPreKeys,
      hasLength(MessengerDeviceService.minUnpublishedPreKeys),
    );
    expect(
      repository.savedPreKeys.map((preKey) => preKey.privateKeyRef),
      everyElement(startsWith('secure-storage:v1:')),
    );
    expect(secretStore.values.values, contains('raw_existing_identity'));
    expect(secretStore.values.values, contains('raw_existing_signed'));
    expect(secretStore.values.values, contains('raw_existing_pre_0'));
  });
}

class _FakeMessengerCryptoBridge implements MessengerCryptoBridge {
  int createdDeviceCount = 0;

  @override
  Future<MessengerDeviceBundle> createDevice(String subjectDid) async {
    createdDeviceCount += 1;
    return MessengerDeviceBundle(
      subjectDid: subjectDid,
      deviceId: 'msgdev_alice',
      identityKeyPublic: 'alice_identity_public',
      identityKeyPrivateRef: 'secure:identity',
      signedPreKeyId: 42,
      signedPreKeyPublic: 'alice_signed_pre_key',
      signedPreKeyPrivateRef: 'secure:signed_pre_key',
      signedPreKeySignature: 'alice_signed_pre_key_signature',
    );
  }

  @override
  Future<List<MessengerCryptoPreKey>> generatePreKeys(
    MessengerDeviceBundle device,
    int count,
  ) async {
    return [
      for (var i = 0; i < count; i += 1)
        MessengerCryptoPreKey(
          preKeyId: 1000 + i,
          publicKey: 'pre_key_public_$i',
          privateKeyRef: 'secure:pre_key_$i',
        ),
    ];
  }

  @override
  Future<MessengerCiphertextEnvelope> encryptInitialMessage(
    MessengerEncryptRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<MessengerPlaintextEnvelope> decryptInboundMessage(
    MessengerDecryptRequest request,
  ) async {
    throw UnimplementedError();
  }
}

class _RawKeyMessengerCryptoBridge implements MessengerCryptoBridge {
  @override
  Future<MessengerDeviceBundle> createDevice(String subjectDid) async {
    return MessengerDeviceBundle(
      subjectDid: subjectDid,
      deviceId: 'msgdev_alice',
      identityKeyPublic: 'alice_identity_public',
      identityKeyPrivateRef: 'raw_identity_private',
      signedPreKeyId: 42,
      signedPreKeyPublic: 'alice_signed_pre_key',
      signedPreKeyPrivateRef: 'raw_signed_pre_key_private',
      signedPreKeySignature: 'alice_signed_pre_key_signature',
    );
  }

  @override
  Future<List<MessengerCryptoPreKey>> generatePreKeys(
    MessengerDeviceBundle device,
    int count,
  ) async {
    return [
      for (var i = 0; i < count; i += 1)
        MessengerCryptoPreKey(
          preKeyId: 1000 + i,
          publicKey: 'pre_key_public_$i',
          privateKeyRef: 'raw_pre_key_private_$i',
        ),
    ];
  }

  @override
  Future<MessengerCiphertextEnvelope> encryptInitialMessage(
    MessengerEncryptRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<MessengerPlaintextEnvelope> decryptInboundMessage(
    MessengerDecryptRequest request,
  ) async {
    throw UnimplementedError();
  }
}

class _RecordingMessengerSecretStore implements MessengerSecretStore {
  final values = <String, String>{};

  @override
  bool isSecretReference(String value) =>
      value.startsWith('secure-storage:v1:');

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

class _RecordingMessengerRelayClient extends MessengerRelayClient {
  _RecordingMessengerRelayClient() : super(baseUrl: 'http://unused.local');

  final publishedDevices = <_PublishedDevice>[];
  final publishedPreKeys = <_PublishedPreKeys>[];

  @override
  Future<void> publishDevice({
    required String subjectDid,
    required String deviceId,
    required Map<String, Object?> bundle,
    required Map<String, Object?> binding,
    required String bindingSignature,
  }) async {
    publishedDevices.add(
      _PublishedDevice(
        subjectDid: subjectDid,
        deviceId: deviceId,
        bundle: bundle,
        binding: binding,
        bindingSignature: bindingSignature,
      ),
    );
  }

  @override
  Future<void> publishPreKeys({
    required String subjectDid,
    required String deviceId,
    required List<Map<String, Object?>> preKeys,
    required String requestSignature,
  }) async {
    publishedPreKeys.add(
      _PublishedPreKeys(
        subjectDid: subjectDid,
        deviceId: deviceId,
        preKeys: preKeys,
        requestSignature: requestSignature,
      ),
    );
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

class _PublishedPreKeys {
  final String subjectDid;
  final String deviceId;
  final List<Map<String, Object?>> preKeys;
  final String requestSignature;

  const _PublishedPreKeys({
    required this.subjectDid,
    required this.deviceId,
    required this.preKeys,
    required this.requestSignature,
  });
}

class _RecordingDidSigner implements DidSigner {
  final messages = <String>[];

  @override
  Future<Ed25519Signature> sign(List<int> message) async {
    messages.add(String.fromCharCodes(message));
    return const Ed25519Signature('aabbcc');
  }
}

class _FakeMessengerRepository implements MessengerRepository {
  _FakeMessengerRepository({
    this.existingDevice,
    List<MessengerPreKeyRecord>? unpublishedPreKeys,
  }) : _unpublishedPreKeys = unpublishedPreKeys ?? [];

  final MessengerDeviceRecord? existingDevice;
  final List<MessengerPreKeyRecord> _unpublishedPreKeys;
  final savedDevices = <MessengerDeviceRecord>[];
  final savedPreKeys = <MessengerPreKeyRecord>[];
  final publishedPreKeys = <(String, int)>[];

  @override
  Future<MessengerDeviceRecord?> localDeviceForSubject(
    String subjectDid,
  ) async {
    return existingDevice?.subjectDid == subjectDid ? existingDevice : null;
  }

  @override
  Future<void> upsertLocalDevice(MessengerDeviceRecord device) async {
    savedDevices.add(device);
  }

  @override
  Future<void> upsertRemoteDevice(MessengerDeviceRecord device) async {}

  @override
  Future<List<MessengerPreKeyRecord>> unpublishedPreKeys(
    String deviceId,
  ) async {
    return _unpublishedPreKeys
        .where((preKey) => preKey.deviceId == deviceId)
        .toList(growable: false);
  }

  @override
  Future<void> savePreKeys(List<MessengerPreKeyRecord> preKeys) async {
    savedPreKeys.addAll(preKeys);
  }

  @override
  Future<void> markPreKeyPublished(String deviceId, int preKeyId) async {
    publishedPreKeys.add((deviceId, preKeyId));
  }

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
  Future<List<MessengerConversationRecord>> conversationList() async {
    return const [];
  }

  @override
  Future<void> saveMessage(MessengerMessageRecord message) async {}

  @override
  Future<List<MessengerMessageRecord>> messagesForConversation(
    String conversationId,
  ) async {
    return const [];
  }

  @override
  Future<String?> mailboxCursorFor(String localDeviceId) async {
    return null;
  }

  @override
  Future<void> saveMailboxCursor(String localDeviceId, String cursor) async {}
}
