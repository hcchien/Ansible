import 'dart:convert';

import 'package:http/http.dart' as http;

import 'relay_identity_client.dart';
import 'web_session_grant_service.dart';

abstract class WebSessionApprovalGateway {
  Future<WebSessionChallenge> fetchChallenge(String challengeId);
  Future<WebSessionApprovalResult> approve(SignedWebSessionGrant signedGrant);
  Future<void> reject(String challengeId);
  Future<List<WebSessionRecord>> fetchSessions(String bearerToken);
  Future<void> revokeSession({
    required String bearerToken,
    String? sessionId,
    String? sessionToken,
  });
}

class WebSessionChallenge {
  final String challengeId;
  final String relayOrigin;
  final String webOrigin;
  final List<String> scopes;
  final DateTime expiresAt;
  final String status;

  const WebSessionChallenge({
    required this.challengeId,
    required this.relayOrigin,
    required this.webOrigin,
    required this.scopes,
    required this.expiresAt,
    required this.status,
  });

  factory WebSessionChallenge.fromJson(Map<String, dynamic> json) {
    final scopes = json['scopes'];
    return WebSessionChallenge(
      challengeId: json['challenge_id'] as String,
      relayOrigin: json['relay_origin'] as String,
      webOrigin: json['web_origin'] as String,
      scopes: scopes is List ? scopes.whereType<String>().toList() : const [],
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      status: json['status'] as String? ?? 'pending',
    );
  }

  bool isExpired(DateTime now) {
    return !expiresAt.isAfter(now.toUtc());
  }
}

class WebSessionApprovalResult {
  final String sessionToken;
  final String trustTier;
  final DateTime expiresAt;

  const WebSessionApprovalResult({
    required this.sessionToken,
    required this.trustTier,
    required this.expiresAt,
  });

  factory WebSessionApprovalResult.fromJson(Map<String, dynamic> json) {
    return WebSessionApprovalResult(
      sessionToken: json['session_token'] as String,
      trustTier: json['trust_tier'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }
}

class WebSessionRecord {
  final String sessionId;
  final String? sessionToken;
  final String subjectDid;
  final String approvingDeviceId;
  final String webOrigin;
  final String relayOrigin;
  final String trustTier;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime expiresAt;

  const WebSessionRecord({
    String? sessionId,
    this.sessionToken,
    required this.subjectDid,
    required this.approvingDeviceId,
    required this.webOrigin,
    required this.relayOrigin,
    required this.trustTier,
    required this.scopes,
    required this.createdAt,
    required this.expiresAt,
  }) : sessionId = sessionId ?? sessionToken ?? '';

  factory WebSessionRecord.fromJson(Map<String, dynamic> json) {
    final scopes = json['scopes'];
    return WebSessionRecord(
      sessionId:
          json['session_id'] as String? ?? json['session_token'] as String?,
      sessionToken: json['session_token'] as String?,
      subjectDid: json['subject_did'] as String,
      approvingDeviceId: json['approving_device_id'] as String,
      webOrigin: json['web_origin'] as String,
      relayOrigin: json['relay_origin'] as String,
      trustTier: json['trust_tier'] as String,
      scopes: scopes is List ? scopes.whereType<String>().toList() : const [],
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }

  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());
}

class WebSessionApprovalException implements Exception {
  final int statusCode;
  final String? error;
  final String? message;
  final Map<String, dynamic> body;

  const WebSessionApprovalException({
    required this.statusCode,
    required this.body,
    this.error,
    this.message,
  });

  @override
  String toString() {
    final label = error ?? 'web_session_approval_error';
    final detail = message == null ? '' : ': $message';
    return 'WebSessionApprovalException($statusCode $label$detail)';
  }
}

class WebSessionApprovalClient implements WebSessionApprovalGateway {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  WebSessionApprovalClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  @override
  Future<WebSessionChallenge> fetchChallenge(String challengeId) async {
    final body = await _getJson('/api/v1/web-sessions/challenges/$challengeId');
    return WebSessionChallenge.fromJson(body);
  }

  @override
  Future<List<WebSessionRecord>> fetchSessions(String bearerToken) async {
    final body = await _getJson(
      '/api/v1/web-sessions',
      headers: {'authorization': 'Bearer $bearerToken'},
    );
    final sessions = body['sessions'];
    if (sessions is! List) return const [];
    return sessions
        .whereType<Map<String, dynamic>>()
        .map(WebSessionRecord.fromJson)
        .toList(growable: false);
  }

  @override
  Future<WebSessionApprovalResult> approve(
    SignedWebSessionGrant signedGrant,
  ) async {
    final body = await _postJson('/api/v1/web-sessions/approve', {
      'challenge_id': signedGrant.grant.challengeId,
      'subject_did': signedGrant.grant.subjectDid,
      'grant': signedGrant.grant.toJson(),
      'signature': signedGrant.signatureHex,
    });
    return WebSessionApprovalResult.fromJson(body);
  }

  @override
  Future<void> reject(String challengeId) async {
    await _postJson('/api/v1/web-sessions/reject', {
      'challenge_id': challengeId,
    });
  }

  @override
  Future<void> revokeSession({
    required String bearerToken,
    String? sessionId,
    String? sessionToken,
  }) async {
    if ((sessionId == null || sessionId.isEmpty) &&
        (sessionToken == null || sessionToken.isEmpty)) {
      throw ArgumentError('sessionId or sessionToken is required');
    }

    await _postJson(
      '/api/v1/web-sessions/revoke',
      sessionId != null && sessionId.isNotEmpty
          ? {'session_id': sessionId}
          : {'session_token': sessionToken},
      headers: {'authorization': 'Bearer $bearerToken'},
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    final response = await _client
        .get(_endpoint(path), headers: headers)
        .timeout(timeout);
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response.statusCode, body);
    }
    return body;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body, {
    Map<String, String>? headers,
  }) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: {'content-type': 'application/json', ...?headers},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response.statusCode, decoded);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String responseBody) {
    if (responseBody.trim().isEmpty) return {};
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Expected JSON object from Relay: $responseBody');
  }

  WebSessionApprovalException _toException(
    int statusCode,
    Map<String, dynamic> body,
  ) {
    return WebSessionApprovalException(
      statusCode: statusCode,
      body: body,
      error: body['error'] as String?,
      message: body['message'] as String?,
    );
  }

  Uri _endpoint(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$path');
  }

  void close() {
    _client.close();
  }
}
