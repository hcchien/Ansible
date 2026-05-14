import 'dart:typed_data';

import 'package:ansible_did/src/rust/frb_generated.dart' as frb;

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

class RustMessengerCryptoBridge implements MessengerCryptoBridge {
  @override
  Future<MessengerDeviceBundle> createDevice(String subjectDid) async {
    final device = await frb.RustLib.instance.apiMessengerCreateDevice(
      subjectDid: subjectDid,
    );
    return _deviceFromRust(device);
  }

  @override
  Future<List<MessengerCryptoPreKey>> generatePreKeys(
    MessengerDeviceBundle device,
    int count,
  ) async {
    final preKeys = await frb.RustLib.instance.apiMessengerGeneratePreKeys(
      device: _deviceToRust(device),
      count: count,
    );
    return preKeys
        .map(
          (preKey) => MessengerCryptoPreKey(
            preKeyId: preKey.preKeyId,
            publicKey: preKey.publicKey,
            privateKeyRef: preKey.privateKey,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<MessengerCiphertextEnvelope> encryptInitialMessage(
    MessengerEncryptRequest request,
  ) async {
    throw UnimplementedError('Messenger encryption is wired in Task 6.');
  }

  @override
  Future<MessengerPlaintextEnvelope> decryptInboundMessage(
    MessengerDecryptRequest request,
  ) async {
    throw UnimplementedError('Messenger decryption is wired in Task 6.');
  }

  MessengerDeviceBundle _deviceFromRust(frb.MessengerDevice device) {
    return MessengerDeviceBundle(
      subjectDid: device.subjectDid,
      deviceId: device.deviceId,
      identityKeyPublic: device.identityKeyPublic,
      identityKeyPrivateRef: device.identityKeyPrivate,
      signedPreKeyId: device.signedPreKeyId,
      signedPreKeyPublic: device.signedPreKeyPublic,
      signedPreKeyPrivateRef: device.signedPreKeyPrivate,
      signedPreKeySignature: device.signedPreKeySignature,
      sessionState: device.sessionState,
    );
  }

  frb.MessengerDevice _deviceToRust(MessengerDeviceBundle device) {
    return frb.MessengerDevice(
      subjectDid: device.subjectDid,
      deviceId: device.deviceId,
      identityKeyPublic: device.identityKeyPublic,
      identityKeyPrivate: device.identityKeyPrivateRef,
      signedPreKeyId: device.signedPreKeyId,
      signedPreKeyPublic: device.signedPreKeyPublic,
      signedPreKeyPrivate: device.signedPreKeyPrivateRef,
      signedPreKeySignature: device.signedPreKeySignature,
      sessionState: device.sessionState,
      oneTimePreKeys: const [],
      nextPreKeyId: 1,
    );
  }
}
