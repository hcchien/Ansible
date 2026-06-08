import 'dart:typed_data';

// ignore: implementation_imports
import 'package:ansible_did/ansible_did.dart' as frb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MessengerDeviceBundle {
  final String subjectDid;
  final String deviceId;
  final String identityKeyPublic;
  final String identityKeyPrivateRef;
  final int signedPreKeyId;
  final String signedPreKeyPublic;
  final String signedPreKeyPrivateRef;
  final String signedPreKeySignature;
  final String? sessionState;

  const MessengerDeviceBundle({
    required this.subjectDid,
    required this.deviceId,
    required this.identityKeyPublic,
    required this.identityKeyPrivateRef,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeyPrivateRef,
    required this.signedPreKeySignature,
    this.sessionState,
  });
}

class MessengerCryptoPreKey {
  final int preKeyId;
  final String publicKey;
  final String privateKeyRef;

  const MessengerCryptoPreKey({
    required this.preKeyId,
    required this.publicKey,
    required this.privateKeyRef,
  });
}

class MessengerEncryptRequest {
  final MessengerDeviceBundle localDevice;
  final Map<String, Object?> remoteBundle;
  final Uint8List plaintext;

  const MessengerEncryptRequest({
    required this.localDevice,
    required this.remoteBundle,
    required this.plaintext,
  });
}

class MessengerDecryptRequest {
  final MessengerDeviceBundle localDevice;
  final MessengerCiphertextEnvelope ciphertext;

  const MessengerDecryptRequest({
    required this.localDevice,
    required this.ciphertext,
  });
}

class MessengerCiphertextEnvelope {
  final String protocolVersion;
  final String ciphertextType;
  final Uint8List ciphertext;
  final String updatedSessionState;

  const MessengerCiphertextEnvelope({
    required this.protocolVersion,
    required this.ciphertextType,
    required this.ciphertext,
    required this.updatedSessionState,
  });
}

class MessengerPlaintextEnvelope {
  final Uint8List body;
  final String updatedSessionState;

  const MessengerPlaintextEnvelope({
    required this.body,
    required this.updatedSessionState,
  });
}

abstract interface class MessengerCryptoBridge {
  Future<MessengerDeviceBundle> createDevice(String subjectDid);

  Future<List<MessengerCryptoPreKey>> generatePreKeys(
    MessengerDeviceBundle device,
    int count,
  );

  Future<MessengerCiphertextEnvelope> encryptInitialMessage(
    MessengerEncryptRequest request,
  );

  Future<MessengerPlaintextEnvelope> decryptInboundMessage(
    MessengerDecryptRequest request,
  );
}

abstract interface class MessengerSecretStore {
  bool isSecretReference(String value);

  Future<String> putSecret({
    required String namespace,
    required String secretId,
    required String secret,
  });

  Future<String> resolveSecret(String value);
}

class SecureStorageMessengerSecretStore implements MessengerSecretStore {
  static const referencePrefix = 'secure-storage:v1:';
  static const _storageKeyPrefix = 'trisaura.messenger.secret.';

  final FlutterSecureStorage _secureStorage;

  const SecureStorageMessengerSecretStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  bool isSecretReference(String value) {
    return value.startsWith(referencePrefix) || value.startsWith('secure:');
  }

  @override
  Future<String> putSecret({
    required String namespace,
    required String secretId,
    required String secret,
  }) async {
    if (isSecretReference(secret)) return secret;
    final reference = '$referencePrefix$namespace:$secretId';
    await _secureStorage.write(
      key: _storageKey(namespace, secretId),
      value: secret,
    );
    return reference;
  }

  @override
  Future<String> resolveSecret(String value) async {
    if (!value.startsWith(referencePrefix)) return value;

    final tail = value.substring(referencePrefix.length);
    final separator = tail.lastIndexOf(':');
    if (separator <= 0 || separator == tail.length - 1) {
      throw StateError('Invalid messenger secret reference.');
    }

    final namespace = tail.substring(0, separator);
    final secretId = tail.substring(separator + 1);
    final secret = await _secureStorage.read(
      key: _storageKey(namespace, secretId),
    );
    if (secret == null) {
      throw StateError('Messenger secret is missing from secure storage.');
    }
    return secret;
  }

  String _storageKey(String namespace, String secretId) {
    return '$_storageKeyPrefix$namespace.$secretId';
  }
}

class RustMessengerCryptoBridge implements MessengerCryptoBridge {
  final MessengerSecretStore secretStore;

  const RustMessengerCryptoBridge({MessengerSecretStore? secretStore})
    : secretStore = secretStore ?? const SecureStorageMessengerSecretStore();

  @override
  Future<MessengerDeviceBundle> createDevice(String subjectDid) async {
    final device = await frb.apiMessengerCreateDevice(
      subjectDid: subjectDid,
    );
    return _deviceFromRust(device);
  }

  @override
  Future<List<MessengerCryptoPreKey>> generatePreKeys(
    MessengerDeviceBundle device,
    int count,
  ) async {
    final rustDevice = await _deviceToRust(device);
    final preKeys = await frb.apiMessengerGeneratePreKeys(
      device: rustDevice,
      count: count,
    );
    final secured = <MessengerCryptoPreKey>[];
    for (final preKey in preKeys) {
      secured.add(
        MessengerCryptoPreKey(
          preKeyId: preKey.preKeyId,
          publicKey: preKey.publicKey,
          privateKeyRef: await secretStore.putSecret(
            namespace: 'prekey.${device.deviceId}',
            secretId: '${preKey.preKeyId}',
            secret: preKey.privateKey,
          ),
        ),
      );
    }
    return secured;
  }

  @override
  Future<MessengerCiphertextEnvelope> encryptInitialMessage(
    MessengerEncryptRequest request,
  ) async {
    final localDevice = await _deviceToRust(request.localDevice);
    final ciphertext = await frb.apiMessengerEncryptInitialMessage(
          input: frb.MessengerEncryptInput(
            localDevice: localDevice,
            remoteBundle: _remoteBundleToRust(request.remoteBundle),
            plaintext: request.plaintext,
          ),
        );
    return MessengerCiphertextEnvelope(
      protocolVersion: ciphertext.protocolVersion,
      ciphertextType: ciphertext.ciphertextType,
      ciphertext: ciphertext.ciphertext,
      updatedSessionState: ciphertext.updatedSessionState,
    );
  }

  @override
  Future<MessengerPlaintextEnvelope> decryptInboundMessage(
    MessengerDecryptRequest request,
  ) async {
    final localDevice = await _deviceToRust(request.localDevice);
    final plaintext = await frb.apiMessengerDecryptInboundMessage(
          localDevice: localDevice,
          ciphertext: frb.MessengerCiphertext(
            protocolVersion: request.ciphertext.protocolVersion,
            ciphertextType: request.ciphertext.ciphertextType,
            ciphertext: request.ciphertext.ciphertext,
            updatedSessionState: request.ciphertext.updatedSessionState,
          ),
        );
    return MessengerPlaintextEnvelope(
      body: plaintext.body,
      updatedSessionState: plaintext.updatedSessionState,
    );
  }

  Future<MessengerDeviceBundle> _deviceFromRust(
    frb.MessengerDevice device,
  ) async {
    return MessengerDeviceBundle(
      subjectDid: device.subjectDid,
      deviceId: device.deviceId,
      identityKeyPublic: device.identityKeyPublic,
      identityKeyPrivateRef: await secretStore.putSecret(
        namespace: 'device.${device.deviceId}',
        secretId: 'identity',
        secret: device.identityKeyPrivate,
      ),
      signedPreKeyId: device.signedPreKeyId,
      signedPreKeyPublic: device.signedPreKeyPublic,
      signedPreKeyPrivateRef: await secretStore.putSecret(
        namespace: 'device.${device.deviceId}',
        secretId: 'signed_pre_key',
        secret: device.signedPreKeyPrivate,
      ),
      signedPreKeySignature: device.signedPreKeySignature,
      sessionState: device.sessionState,
    );
  }

  Future<frb.MessengerDevice> _deviceToRust(
    MessengerDeviceBundle device,
  ) async {
    return frb.MessengerDevice(
      subjectDid: device.subjectDid,
      deviceId: device.deviceId,
      identityKeyPublic: device.identityKeyPublic,
      identityKeyPrivate: await secretStore.resolveSecret(
        device.identityKeyPrivateRef,
      ),
      signedPreKeyId: device.signedPreKeyId,
      signedPreKeyPublic: device.signedPreKeyPublic,
      signedPreKeyPrivate: await secretStore.resolveSecret(
        device.signedPreKeyPrivateRef,
      ),
      signedPreKeySignature: device.signedPreKeySignature,
      sessionState: device.sessionState,
      oneTimePreKeys: const [],
      nextPreKeyId: 1,
    );
  }

  frb.MessengerPreKeyBundle _remoteBundleToRust(
    Map<String, Object?> remoteBundle,
  ) {
    return frb.MessengerPreKeyBundle(
      subjectDid: _string(remoteBundle, 'subject_did'),
      deviceId: _string(remoteBundle, 'device_id'),
      identityKey: _string(
        remoteBundle,
        'identity_key',
        fallbackKey: 'messenger_identity_key',
      ),
      signedPreKeyId: _int(remoteBundle, 'signed_pre_key_id'),
      signedPreKey: _string(remoteBundle, 'signed_pre_key'),
      signedPreKeySignature: _string(remoteBundle, 'signed_pre_key_signature'),
      oneTimePreKeyId: _int(remoteBundle, 'one_time_pre_key_id'),
      oneTimePreKey: _string(remoteBundle, 'one_time_pre_key'),
    );
  }

  String _string(
    Map<String, Object?> value,
    String key, {
    String? fallbackKey,
  }) {
    final raw = value[key] ?? (fallbackKey == null ? null : value[fallbackKey]);
    if (raw is String && raw.isNotEmpty) return raw;
    throw ArgumentError('Missing messenger bundle string "$key"');
  }

  int _int(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    throw ArgumentError('Missing messenger bundle integer "$key"');
  }
}
