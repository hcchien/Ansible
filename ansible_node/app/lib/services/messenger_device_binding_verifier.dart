import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';

import 'messenger_relay_client.dart';

class MessengerDidVerificationKey {
  const MessengerDidVerificationKey({
    required this.publicKeyHex,
    required this.algorithm,
  });

  final String publicKeyHex;
  final String algorithm;
}

typedef MessengerDidVerificationKeyResolver =
    Future<MessengerDidVerificationKey?> Function(String did);

typedef MessengerBindingSignatureVerifier =
    Future<bool> Function({
      required MessengerDidVerificationKey key,
      required List<int> message,
      required String signatureHex,
    });

abstract interface class MessengerDeviceBindingVerifier {
  Future<void> verify({
    required String subjectDid,
    required MessengerPreKeyBundleDevice device,
  });
}

class DidMessengerDeviceBindingVerifier
    implements MessengerDeviceBindingVerifier {
  DidMessengerDeviceBindingVerifier({
    required MessengerDidVerificationKeyResolver resolveVerificationKey,
    MessengerBindingSignatureVerifier? verifySignature,
  }) : _resolveVerificationKey = resolveVerificationKey,
       _verifySignature = verifySignature ?? _defaultVerifySignature;

  final MessengerDidVerificationKeyResolver _resolveVerificationKey;
  final MessengerBindingSignatureVerifier _verifySignature;

  @override
  Future<void> verify({
    required String subjectDid,
    required MessengerPreKeyBundleDevice device,
  }) async {
    final expectedBinding = <String, Object?>{
      'type': 'io.trisaura.messengerDeviceBinding',
      'version': 1,
      'subject_did': subjectDid,
      'device_id': device.deviceId,
      'messenger_identity_key': device.messengerIdentityKey,
      'signed_pre_key_id': device.signedPreKeyId,
      'signed_pre_key': device.signedPreKey,
    };
    if (!_deepEquals(device.binding, expectedBinding)) {
      throw MessengerDeviceBindingInvalid(
        subjectDid: subjectDid,
        deviceId: device.deviceId,
        reason: 'binding_mismatch',
      );
    }

    final signature = device.bindingSignature;
    final key = await _resolveVerificationKey(subjectDid);
    if (signature == null || signature.isEmpty || key == null) {
      throw MessengerDeviceBindingInvalid(
        subjectDid: subjectDid,
        deviceId: device.deviceId,
        reason: 'verification_key_unavailable',
      );
    }
    final valid = await _verifySignature(
      key: key,
      message: utf8.encode(_canonicalJson(expectedBinding)),
      signatureHex: signature,
    );
    if (!valid) {
      throw MessengerDeviceBindingInvalid(
        subjectDid: subjectDid,
        deviceId: device.deviceId,
        reason: 'invalid_signature',
      );
    }
  }

  static Future<bool> _defaultVerifySignature({
    required MessengerDidVerificationKey key,
    required List<int> message,
    required String signatureHex,
  }) {
    if (key.algorithm != 'ed25519' && key.algorithm != 'p256-sha256') {
      return Future.value(false);
    }
    return DidSigner.verify(
      publicKeyHex: key.publicKeyHex,
      message: message,
      signature: Ed25519Signature(signatureHex),
    );
  }

  bool _deepEquals(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_deepEquals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index += 1) {
        if (!_deepEquals(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
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

class MessengerDeviceBindingInvalid implements Exception {
  const MessengerDeviceBindingInvalid({
    required this.subjectDid,
    required this.deviceId,
    required this.reason,
  });

  final String subjectDid;
  final String deviceId;
  final String reason;

  @override
  String toString() =>
      'MessengerDeviceBindingInvalid(subjectDid: $subjectDid, '
      'deviceId: $deviceId, reason: $reason)';
}
