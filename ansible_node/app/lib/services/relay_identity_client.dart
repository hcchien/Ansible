import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

const kDefaultRelayBaseUrl = AppEnvironment.defaultRelayBaseUrl;

const kDevZkpCircuitVersion = 'passport_v1_dev';
const kDevVerificationKeyHash = 'sha256:dev-passport-v1-placeholder';

class IdentityChallenge {
  final String did;
  final String challenge;
  final String expiresAt;

  const IdentityChallenge({
    required this.did,
    required this.challenge,
    required this.expiresAt,
  });
}

class IdentityAnchorResult {
  final bool verified;
  final String did;
  final String expiresAt;

  const IdentityAnchorResult({
    required this.verified,
    required this.did,
    required this.expiresAt,
  });
}

class IdentityAnchorRequest {
  final String did;
  final String zkpProof;
  final String zkpCircuitVersion;
  final String verificationKeyHash;
  final String nullifier;
  final String publicKeyHex;
  final String challenge;
  final String challengeSignatureHex;

  const IdentityAnchorRequest({
    required this.did,
    required this.zkpProof,
    required this.zkpCircuitVersion,
    required this.verificationKeyHash,
    required this.nullifier,
    required this.publicKeyHex,
    required this.challenge,
    required this.challengeSignatureHex,
  });

  Map<String, Object?> toJson() {
    return {
      'did': did,
      'zkp_proof': zkpProof,
      'zkp_circuit_version': zkpCircuitVersion,
      'verification_key_hash': verificationKeyHash,
      'nullifier': nullifier,
      'public_key': publicKeyHex,
      'challenge': challenge,
      'challenge_signature': challengeSignatureHex,
    };
  }
}

class RelayIdentityException implements Exception {
  final int statusCode;
  final String? error;
  final String? message;
  final List<String> fields;
  final String responseBody;

  const RelayIdentityException({
    required this.statusCode,
    required this.responseBody,
    this.error,
    this.message,
    this.fields = const [],
  });

  @override
  String toString() {
    final label = error ?? 'relay_identity_error';
    final detail = message == null ? '' : ': $message';
    final fieldText = fields.isEmpty ? '' : ' (${fields.join(', ')})';
    return 'RelayIdentityException($statusCode $label$detail$fieldText)';
  }
}

class RelayIdentityClient {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  RelayIdentityClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  Future<IdentityChallenge> issueChallenge(String did) async {
    final body = await _postJson('/api/v1/identity/challenge', {
      'did': did,
    }, expectedStatus: 200);

    return IdentityChallenge(
      did: body['did'] as String,
      challenge: body['challenge'] as String,
      expiresAt: body['expires_at'] as String,
    );
  }

  Future<IdentityAnchorResult> anchor(IdentityAnchorRequest request) async {
    final body = await _postJson(
      '/api/v1/identity/anchor',
      request.toJson(),
      expectedStatus: 200,
    );

    return IdentityAnchorResult(
      verified: body['verified'] as bool,
      did: body['did'] as String,
      expiresAt: body['expires_at'] as String,
    );
  }

  /// Fetch the verified public key hex for a registered DID from the relay.
  /// Returns null if the DID is not registered (404).
  Future<String?> fetchPublicKey(String did) async {
    try {
      final response = await _client
          .get(_endpoint('/api/v1/identity/public-key/${Uri.encodeComponent(did)}'))
          .timeout(timeout);
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw RelayIdentityException(
          statusCode: response.statusCode,
          responseBody: response.body,
          error: 'public_key_fetch_failed',
        );
      }
      final decoded = _decodeObject(response.body);
      return decoded['public_key_hex'] as String?;
    } on RelayIdentityException {
      rethrow;
    } catch (e) {
      throw RelayIdentityException(
        statusCode: 0,
        responseBody: e.toString(),
        error: 'network_error',
      );
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body, {
    required int expectedStatus,
  }) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    final decoded = _decodeObject(response.body);
    if (response.statusCode != expectedStatus) {
      throw _toRelayException(response.statusCode, response.body, decoded);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Expected JSON object from Relay: $responseBody');
  }

  RelayIdentityException _toRelayException(
    int statusCode,
    String responseBody,
    Map<String, dynamic> decoded,
  ) {
    final rawFields = decoded['fields'];
    return RelayIdentityException(
      statusCode: statusCode,
      responseBody: responseBody,
      error: decoded['error'] as String?,
      message: decoded['message'] as String?,
      fields: rawFields is List
          ? rawFields.whereType<String>().toList()
          : const [],
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
