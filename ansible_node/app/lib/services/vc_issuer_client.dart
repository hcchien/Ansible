import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP client for the Tris-Aura Issuer Server (ansible_issuer).
///
/// Endpoints:
///   POST /api/v1/vc/request — request an email OTP
///   POST /api/v1/vc/issue   — verify OTP and receive a signed W3C VC

// ─── Model classes ────────────────────────────────────────────────────────────

class VcIssuanceChallenge {
  /// Human-readable status hint from the server.
  final String hint;

  /// OTP returned by the server in mock mode (null in production).
  final String? otp;

  const VcIssuanceChallenge({required this.hint, this.otp});

  factory VcIssuanceChallenge.fromJson(Map<String, dynamic> json) =>
      VcIssuanceChallenge(
        hint: json['hint'] as String? ?? '',
        otp: json['otp'] as String?,
      );

  /// True when the server is running in mock mode and returned the OTP directly.
  bool get isMockOtp => otp != null;
}

class VcIssuerException implements Exception {
  final int statusCode;
  final String error;

  const VcIssuerException({required this.statusCode, required this.error});

  @override
  String toString() => 'VcIssuerException($statusCode $error)';
}

// ─── Client ──────────────────────────────────────────────────────────────────

class VcIssuerClient {
  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  VcIssuerClient({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(
          baseUrl ??
              const String.fromEnvironment(
                'ANSIBLE_ISSUER_BASE_URL',
                defaultValue: 'http://localhost:4002',
              ),
        ),
        _client = client ?? http.Client();

  /// POST /api/v1/vc/request
  ///
  /// Requests an OTP for [email] on behalf of [did].
  /// In mock mode the returned [VcIssuanceChallenge.otp] field is non-null and
  /// can be passed directly to [issueCredential].
  Future<VcIssuanceChallenge> requestEmailVerification({
    required String did,
    required String email,
  }) async {
    final body = await _postJson('/api/v1/vc/request', {
      'did': did,
      'email': email,
    });
    return VcIssuanceChallenge.fromJson(body);
  }

  /// POST /api/v1/vc/issue
  ///
  /// Verifies [otp] and returns the raw W3C VC JSON map.
  /// Callers should parse this with [VerifiableCredential.fromJson].
  Future<Map<String, dynamic>> issueCredential({
    required String did,
    required String email,
    required String otp,
  }) async {
    final body = await _postJson('/api/v1/vc/issue', {
      'did': did,
      'email': email,
      'otp': otp,
    });
    return body['vc'] as Map<String, dynamic>;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VcIssuerException(
        statusCode: response.statusCode,
        error: (decoded['error'] as String?) ?? 'unknown_error',
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Expected JSON object from Issuer server');
  }

  Uri _endpoint(String path) {
    final base = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$base$path');
  }

  void close() => _client.close();
}
