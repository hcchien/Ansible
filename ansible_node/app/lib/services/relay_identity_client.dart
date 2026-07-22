import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/protocol.dart';

const kDefaultRelayBaseUrl = AppEnvironment.defaultRelayBaseUrl;

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

/// Reads a registered DID's verification key from the relay.
///
/// The Phase 1 ZKP challenge/anchor methods this client used to host were
/// retired with the V1 identity flow (did:elix + the self-certifying anchor
/// replaced them). Only the public-key lookup remains, used for signature
/// verification during sync.
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

  /// Fetch the verified public key hex for a registered DID from the relay.
  /// Returns null if the DID is not registered (404).
  Future<String?> fetchPublicKey(String did) async {
    final key = await fetchVerificationKey(did);
    return key?.publicKeyHex;
  }

  Future<RelayVerificationKey?> fetchVerificationKey(String did) async {
    try {
      final response = await _client
          .get(
            _endpoint(
              '/api/v1/identity/public-key/${Uri.encodeComponent(did)}',
            ),
            headers: AnsibleProtocol.headers,
          )
          .timeout(timeout);
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        final decoded = _tryDecodeObject(response.body);
        throw RelayIdentityException(
          statusCode: response.statusCode,
          responseBody: response.body,
          error: decoded?['error'] as String? ?? 'public_key_fetch_failed',
          message: decoded?['message'] as String?,
        );
      }
      final decoded = _decodeObject(response.body);
      final publicKeyHex = decoded['public_key_hex'] as String?;
      if (publicKeyHex == null) return null;
      return RelayVerificationKey(
        publicKeyHex: publicKeyHex,
        signingAlgorithm: decoded['signing_algorithm'] as String? ?? 'ed25519',
        keyVersion: decoded['key_version'] as int? ?? 1,
      );
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

  Map<String, dynamic> _decodeObject(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Expected JSON object from Relay: $responseBody');
  }

  Map<String, dynamic>? _tryDecodeObject(String responseBody) {
    try {
      return _decodeObject(responseBody);
    } on FormatException {
      return null;
    }
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

class RelayVerificationKey {
  const RelayVerificationKey({
    required this.publicKeyHex,
    required this.signingAlgorithm,
    required this.keyVersion,
  });

  final String publicKeyHex;
  final String signingAlgorithm;
  final int keyVersion;
}
