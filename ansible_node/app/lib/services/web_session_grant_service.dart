import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class WebSessionGrant {
  static const type = 'io.trisaura.webSessionGrant';
  static const version = 1;

  final String challengeId;
  final String relayOrigin;
  final String webOrigin;
  final String subjectDid;
  final String approvingDeviceId;
  final List<String> scopes;
  final DateTime expiresAt;
  final DateTime createdAt;

  const WebSessionGrant({
    required this.challengeId,
    required this.relayOrigin,
    required this.webOrigin,
    required this.subjectDid,
    required this.approvingDeviceId,
    required this.scopes,
    required this.expiresAt,
    required this.createdAt,
  });

  Map<String, Object?> toJson() {
    return {
      'type': type,
      'version': version,
      'challenge_id': challengeId,
      'relay_origin': relayOrigin,
      'web_origin': webOrigin,
      'subject_did': subjectDid,
      'approving_device_id': approvingDeviceId,
      'scopes': scopes,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  String canonicalJson() {
    return jsonEncode({
      'approving_device_id': approvingDeviceId,
      'challenge_id': challengeId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'relay_origin': relayOrigin,
      'scopes': scopes,
      'subject_did': subjectDid,
      'type': type,
      'version': version,
      'web_origin': webOrigin,
    });
  }
}

abstract class WebSessionDeviceIdProvider {
  Future<String> getOrCreateDeviceId();
}

class SecureStorageWebSessionDeviceIdProvider
    implements WebSessionDeviceIdProvider {
  static const _storageKey = 'trisaura.web_session.approving_device_id';

  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;

  const SecureStorageWebSessionDeviceIdProvider({
    FlutterSecureStorage? secureStorage,
    Uuid uuid = const Uuid(),
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _uuid = uuid;

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final created = 'app_device_${_uuid.v4()}';
    await _secureStorage.write(key: _storageKey, value: created);
    return created;
  }
}

class SignedWebSessionGrant {
  final WebSessionGrant grant;
  final String signatureHex;

  const SignedWebSessionGrant({
    required this.grant,
    required this.signatureHex,
  });
}

abstract class WebSessionGrantSigner {
  Future<SignedWebSessionGrant> sign(WebSessionGrant grant);
}

class WebSessionGrantService implements WebSessionGrantSigner {
  final DidSigner signer;

  WebSessionGrantService({DidSigner? signer})
    : signer = signer ?? DidSignerImpl();

  @override
  Future<SignedWebSessionGrant> sign(WebSessionGrant grant) async {
    final signature = await signer.sign(utf8.encode(grant.canonicalJson()));
    return SignedWebSessionGrant(grant: grant, signatureHex: signature.hex);
  }
}

class WebSessionApprovalLink {
  final String challengeId;
  final String relayOrigin;

  const WebSessionApprovalLink({
    required this.challengeId,
    required this.relayOrigin,
  });

  static WebSessionApprovalLink parse(Uri uri) {
    final isApprovalPath =
        uri.scheme == 'trisaura' &&
        uri.host == 'web-session' &&
        uri.path == '/approve';
    if (!isApprovalPath) {
      throw const FormatException(
        'Expected Tris-Aura web session approval link',
      );
    }

    final challengeId = uri.queryParameters['challenge_id'];
    final relayOrigin = uri.queryParameters['relay_origin'];
    if (challengeId == null || challengeId.trim().isEmpty) {
      throw const FormatException('Missing web session challenge id');
    }
    if (relayOrigin == null || relayOrigin.trim().isEmpty) {
      throw const FormatException('Missing relay origin');
    }

    final parsedRelayOrigin = Uri.tryParse(relayOrigin);
    final validRelayOrigin =
        parsedRelayOrigin != null &&
        (parsedRelayOrigin.scheme == 'https' ||
            parsedRelayOrigin.scheme == 'http') &&
        parsedRelayOrigin.host.isNotEmpty;
    if (!validRelayOrigin) {
      throw const FormatException('Invalid relay origin');
    }

    return WebSessionApprovalLink(
      challengeId: challengeId,
      relayOrigin: relayOrigin,
    );
  }
}
