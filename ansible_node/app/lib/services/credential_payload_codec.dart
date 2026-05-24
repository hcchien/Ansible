import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialPayloadEnvelope {
  const CredentialPayloadEnvelope({
    required this.encodedPayload,
    required this.encryptionVersion,
  });

  final String encodedPayload;
  final String encryptionVersion;
}

class SecureCredentialPayloadCodec {
  static const version = 'secure-storage-json-v1';
  static const _storageKeyPrefix = 'trisaura.wallet.credential_payload.';
  static const _referencePrefix = '$version:';

  final FlutterSecureStorage _secureStorage;

  const SecureCredentialPayloadCodec({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<CredentialPayloadEnvelope> seal({
    required String credentialId,
    required String payloadJson,
  }) async {
    await _secureStorage.write(
      key: _storageKey(credentialId),
      value: payloadJson,
    );
    return CredentialPayloadEnvelope(
      encodedPayload: '$_referencePrefix$credentialId',
      encryptionVersion: version,
    );
  }

  Future<Map<String, Object?>> decode(String encodedPayload) async {
    final payloadJson = await _payloadJson(encodedPayload);
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw const FormatException(
      'Credential payload must decode to a JSON object.',
    );
  }

  Future<String> _payloadJson(String encodedPayload) async {
    if (!encodedPayload.startsWith(_referencePrefix)) {
      return encodedPayload;
    }

    final credentialId = encodedPayload.substring(_referencePrefix.length);
    final payloadJson = await _secureStorage.read(
      key: _storageKey(credentialId),
    );
    if (payloadJson == null || payloadJson.isEmpty) {
      throw StateError('Credential payload is missing from secure storage.');
    }
    return payloadJson;
  }

  static String _storageKey(String credentialId) {
    return '$_storageKeyPrefix$credentialId';
  }
}
