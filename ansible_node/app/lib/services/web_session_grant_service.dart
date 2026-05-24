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

  static WebSessionApprovalLink parse(
    Uri uri, {
    Set<String>? allowedRelayOrigins,
    bool allowLocalHttp = false,
  }) {
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
    final normalizedRelayOrigin = _normalizeOrigin(parsedRelayOrigin);
    final host = parsedRelayOrigin?.host.toLowerCase() ?? '';
    // Reject RFC-1918 LAN addresses unconditionally — allowLocalHttp only
    // permits genuine loopback addresses (localhost / 127.x / ::1).
    final isLoopbackHttp =
        parsedRelayOrigin != null &&
        allowLocalHttp &&
        _isLocalHttpOrigin(parsedRelayOrigin);
    final validRelayOrigin =
        parsedRelayOrigin != null &&
        host.isNotEmpty &&
        (isLoopbackHttp || !_isPrivateOrLocalHost(host)) &&
        (parsedRelayOrigin.scheme == 'https' || isLoopbackHttp);
    if (!validRelayOrigin) {
      throw const FormatException('Invalid relay origin');
    }
    if (allowedRelayOrigins != null &&
        !allowedRelayOrigins
            .map(_normalizeOriginString)
            .contains(normalizedRelayOrigin)) {
      throw const FormatException('Relay origin is not allowed');
    }

    return WebSessionApprovalLink(
      challengeId: challengeId,
      relayOrigin: normalizedRelayOrigin,
    );
  }

  static String _normalizeOrigin(Uri? uri) {
    if (uri == null) return '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port';
  }

  static String _normalizeOriginString(String origin) {
    return _normalizeOrigin(Uri.tryParse(origin));
  }

  static bool _isLocalHttpOrigin(Uri uri) {
    if (uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    // Only permit known loopback addresses. RFC-1918 ranges and arbitrary
    // hostnames are excluded to prevent a malicious deep link from directing
    // the app at an attacker-controlled LAN host.
    return host == 'localhost' || host == '::1' || host.startsWith('127.');
  }

  static bool _isPrivateOrLocalHost(String host) {
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '0.0.0.0' ||
        host == '::1') {
      return true;
    }
    if (host.startsWith('127.')) return true;
    if (host.startsWith('10.')) return true;
    if (host.startsWith('192.168.')) return true;
    if (host.startsWith('169.254.')) return true;

    final parts = host.split('.');
    if (parts.length == 4) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      if (first == 172 && second != null && second >= 16 && second <= 31) {
        return true;
      }
      if (first == 100 && second != null && second >= 64 && second <= 127) {
        return true;
      }
    }

    final isIpv6 = host.contains(':');
    return isIpv6 &&
        (host.startsWith('fc') ||
            host.startsWith('fd') ||
            host.startsWith('fe80:'));
  }
}
