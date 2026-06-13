import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A platform push token (FCM on Android, APNS on iOS).
class PushDeviceToken {
  final String token;
  final String platform; // "fcm" | "apns"

  const PushDeviceToken({required this.token, required this.platform});
}

/// Source of the platform push token. The real implementation wraps the
/// platform push plugin (FCM/APNS) and requires per-app platform config
/// (Firebase project / APNS key) — see docs/getting-started-dev.md. Until
/// that config exists, [UnavailablePushTokenProvider] keeps the feature
/// visibly "not configured" instead of silently broken.
abstract class PushTokenProvider {
  /// Returns null when push is unavailable (no platform config, simulator,
  /// permission denied).
  Future<PushDeviceToken?> currentToken();
}

class UnavailablePushTokenProvider implements PushTokenProvider {
  const UnavailablePushTokenProvider();

  @override
  Future<PushDeviceToken?> currentToken() async => null;
}

/// Registers/unregisters this device for content-free wake pushes with the
/// relay (`POST /api/v1/push/tokens` / `/unregister`).
///
/// Constitution note (notification plan, Base Rule 2): the relay only ever
/// pushes `{"hint": "sync"}` — notification content is composed on-device
/// from the local notifications table. Registering reveals only "this DID
/// has a device that wants wake-ups". Disabling push deletes the token
/// server-side.
class PushRegistrationService {
  PushRegistrationService({
    required String baseUrl,
    PushTokenProvider tokenProvider = const UnavailablePushTokenProvider(),
    DidSigner? signer,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUri = Uri.parse(baseUrl),
       _tokenProvider = tokenProvider,
       _signer = signer ?? DidSignerImpl(),
       _client = client ?? http.Client();

  final Uri _baseUri;
  final PushTokenProvider _tokenProvider;
  final DidSigner _signer;
  final http.Client _client;
  final Duration timeout;

  static const _deviceIdKey = 'elix-push-device-id';

  /// Stable per-install device id (independent from messenger device ids so
  /// either feature can be reset without breaking the other).
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = const Uuid().v4();
    await prefs.setString(_deviceIdKey, fresh);
    return fresh;
  }

  /// Whether a platform push token is currently obtainable.
  Future<bool> available() async =>
      (await _tokenProvider.currentToken()) != null;

  /// Registers (or updates) this device's wake-push token. Returns false
  /// when no platform token is available (push not configured).
  Future<bool> register({
    required String did,
    required List<String> categories,
  }) async {
    final deviceToken = await _tokenProvider.currentToken();
    if (deviceToken == null) return false;

    // Keys listed alphabetically to match the relay's sorted-key canonical
    // JSON signature verification (same convention as signed intents).
    final payload = <String, Object?>{
      'categories': List<String>.from(categories)..sort(),
      'device_id': await deviceId(),
      'platform': deviceToken.platform,
      'push_token': deviceToken.token,
      'registered_at': DateTime.now().toUtc().toIso8601String(),
      'subject_did': did,
    };
    await _postSigned('/api/v1/push/tokens', payload, accept: const {200, 201});
    return true;
  }

  /// Deletes this device's token server-side (mandatory exit path).
  Future<void> unregister({required String did}) async {
    final payload = <String, Object?>{
      'device_id': await deviceId(),
      'subject_did': did,
      'unregistered_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _postSigned(
      '/api/v1/push/tokens/unregister',
      payload,
      accept: const {200},
    );
  }

  Future<void> _postSigned(
    String path,
    Map<String, Object?> payload, {
    required Set<int> accept,
  }) async {
    final signature = await _signer
        .sign(utf8.encode(jsonEncode(payload)))
        .then((signature) => signature.hex);
    final response = await _client
        .post(
          _endpoint(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({...payload, 'request_signature': signature}),
        )
        .timeout(timeout);
    if (!accept.contains(response.statusCode)) {
      throw PushRegistrationException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Uri _endpoint(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }

  void close() => _client.close();
}

class PushRegistrationException implements Exception {
  final int statusCode;
  final String body;

  const PushRegistrationException({
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() => 'PushRegistrationException($statusCode)';
}
