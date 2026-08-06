import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../config/protocol.dart';
import 'platform_capabilities.dart';

abstract class WebAuthnPlatform {
  Future<Map<String, dynamic>> register(Map<String, dynamic> options);
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options);
}

class NativeWebAuthnPlatform implements WebAuthnPlatform {
  NativeWebAuthnPlatform({PasskeyAuthenticator? authenticator})
    : _authenticator = authenticator ?? PasskeyAuthenticator();

  final PasskeyAuthenticator _authenticator;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    final result = await _authenticator.register(
      RegisterRequestType.fromJson(options),
    );
    return result.toJson();
  }

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> options,
  ) async {
    final result = await _authenticator.authenticate(
      AuthenticateRequestType.fromJson(options),
    );
    return result.toJson();
  }
}

class SyncCapability {
  const SyncCapability({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  bool isValid(DateTime now) => expiresAt.isAfter(now.toUtc());
}

class SyncCapabilityException implements Exception {
  const SyncCapabilityException(this.statusCode, this.error);

  final int statusCode;
  final String error;

  bool get requiresEnrollment =>
      statusCode == 409 && error == 'passkey_not_enrolled';

  @override
  String toString() => 'SyncCapabilityException($statusCode $error)';
}

class SyncCapabilityService {
  SyncCapabilityService({
    required String baseUrl,
    required String holderDid,
    WebAuthnPlatform? platform,
    DidSigner? didSigner,
    http.Client? client,
    DateTime Function()? now,
    PlatformCapabilities? platformCapabilities,
  }) : _baseUri = Uri.parse(baseUrl),
       _holderDid = holderDid,
       _platform = platform ?? NativeWebAuthnPlatform(),
       _didSigner = didSigner ?? DidSignerImpl(),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _platformCapabilities =
           platformCapabilities ?? PlatformCapabilities.current;

  final Uri _baseUri;
  final String _holderDid;
  final WebAuthnPlatform _platform;
  final DidSigner _didSigner;
  final http.Client _client;
  final DateTime Function() _now;
  final PlatformCapabilities _platformCapabilities;

  SyncCapability? _cached;
  Future<SyncCapability>? _authorizationInFlight;

  Future<SyncCapability> authorize({bool allowEnrollment = true}) {
    if (!_platformCapabilities.webAuthn) {
      return Future.error(
        const SyncCapabilityException(409, 'webauthn_unavailable'),
      );
    }
    final cached = _cached;
    if (cached != null &&
        cached.expiresAt.isAfter(
          _now().toUtc().add(const Duration(seconds: 15)),
        )) {
      return Future.value(cached);
    }

    final inFlight = _authorizationInFlight;
    if (inFlight != null) return inFlight;

    final authorization = _authorizeUncached(allowEnrollment: allowEnrollment);
    _authorizationInFlight = authorization;
    void clearInFlight() {
      if (identical(_authorizationInFlight, authorization)) {
        _authorizationInFlight = null;
      }
    }

    // Avoid `whenComplete` here because it creates a second failing Future
    // when authorization fails, even if the caller handles the original.
    authorization.then<void>(
      (_) => clearInFlight(),
      onError: (Object _, StackTrace _) => clearInFlight(),
    );
    return authorization;
  }

  Future<SyncCapability> _authorizeUncached({
    required bool allowEnrollment,
  }) async {
    Map<String, dynamic> challenge;
    try {
      challenge = await _post('/api/v2/webauthn/authenticate/options', {
        'did': _holderDid,
        'scope': 'sync:write',
      });
    } on SyncCapabilityException catch (error) {
      if (!allowEnrollment || !error.requiresEnrollment) rethrow;
      await _enroll();
      challenge = await _post('/api/v2/webauthn/authenticate/options', {
        'did': _holderDid,
        'scope': 'sync:write',
      });
    }

    final assertion = await _platform.authenticate(
      _publicKeyOptions(challenge),
    );
    final exchanged = await _post('/api/v2/webauthn/authenticate/exchange', {
      'did': _holderDid,
      'scope': 'sync:write',
      'challenge_id': challenge['challenge_id'],
      'credential': assertion,
    });
    final expiresIn = (exchanged['expires_in'] as num?)?.toInt() ?? 0;
    final capability = SyncCapability(
      token: exchanged['token'] as String,
      expiresAt: _now().toUtc().add(Duration(seconds: expiresIn)),
    );
    _cached = capability;
    return capability;
  }

  Future<void> _enroll() async {
    final challenge = await _post('/api/v2/webauthn/register/options', {
      'did': _holderDid,
    });
    final credential = await _platform.register(_publicKeyOptions(challenge));
    final rawId = (credential['rawId'] ?? credential['id']) as String;
    final challengeId = challenge['challenge_id'] as String;
    final credentialId = base64Url.decode(base64Url.normalize(rawId));
    final credentialIdHash = sha256.convert(credentialId).toString();
    final delegationId =
        'wcd_${sha256.convert(utf8.encode('$_holderDid\u0000$rawId')).toString().substring(0, 32)}';
    final issuedAt = _now().toUtc();
    final delegation = <String, Object?>{
      'type': 'io.trisaura.identity.webCredentialDelegation',
      'version': 1,
      'delegation_id': delegationId,
      'challenge_id': challengeId,
      'subject_did': _holderDid,
      'credential_id_hash': credentialIdHash,
      'rp_id': (challenge['publicKey'] as Map)['rp']['id'] as String,
      'issued_at': issuedAt.toIso8601String(),
      'expires_at': issuedAt.add(const Duration(days: 90)).toIso8601String(),
      'allowed_actions': const [
        'forum.publish',
        'forum.reply',
        'forum.edit',
        'forum.delete',
        'forum.react',
        'forum.moderate',
      ],
    };
    final didProof = await _didSigner.sign(
      utf8.encode(_canonicalJson(delegation)),
    );
    await _post('/api/v2/webauthn/register/finish', {
      'did': _holderDid,
      'challenge_id': challengeId,
      'credential': credential,
      'did_signature': didProof.hex,
      'delegation': delegation,
    });
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()),
        );
      return '{${entries.map((entry) => '${jsonEncode(entry.key.toString())}:${_canonicalJson(entry.value)}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }

  Map<String, dynamic> _publicKeyOptions(Map<String, dynamic> body) {
    final options = body['publicKey'];
    if (options is Map<String, dynamic>) return options;
    throw const FormatException('Relay WebAuthn response has no publicKey');
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client.post(
      _endpoint(path),
      headers: const {
        'content-type': 'application/json',
        ...AnsibleProtocol.headers,
      },
      body: jsonEncode(body),
    );
    Map<String, dynamic> object;
    try {
      final decoded = jsonDecode(response.body);
      object = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      throw SyncCapabilityException(
        response.statusCode,
        response.statusCode >= 200 && response.statusCode < 300
            ? 'invalid_response'
            : 'webauthn_error',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncCapabilityException(
        response.statusCode,
        object['error'] as String? ?? 'webauthn_error',
      );
    }
    return object;
  }

  Uri _endpoint(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }
}
