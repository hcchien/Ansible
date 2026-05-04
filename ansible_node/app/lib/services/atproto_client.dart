import 'dart:convert';

import 'package:http/http.dart' as http;

/// AT Protocol XRPC client for Tris-Aura V2.0.
///
/// Implements the subset of AT Protocol HTTP API used by the App:
///   - POST /api/v2/identity/register  (Passkeys registration)
///   - POST /api/v2/identity/anchor    (DID activation)
///   - POST /xrpc/com.atproto.repo.createRecord  (publish Lexicon record)
///   - GET  /xrpc/com.atproto.identity.resolveHandle (handle → DID)

// ─── Model classes ────────────────────────────────────────────────────────────

class RegistrationChallenge {
  final String nonce;
  final String expiresAt;
  final String? handle;

  const RegistrationChallenge({
    required this.nonce,
    required this.expiresAt,
    this.handle,
  });

  factory RegistrationChallenge.fromJson(Map<String, dynamic> json) {
    return RegistrationChallenge(
      nonce: json['nonce'] as String,
      expiresAt: json['expires_at'] as String,
      handle: json['handle'] as String?,
    );
  }
}

class AnchorRequest {
  final String did;
  final String publicKeyHex;
  final String handle;
  final String registrationSig;
  final String nonce;

  const AnchorRequest({
    required this.did,
    required this.publicKeyHex,
    required this.handle,
    required this.registrationSig,
    required this.nonce,
  });

  Map<String, Object?> toJson() => {
    'did': did,
    'public_key_hex':
        publicKeyHex, // must match server params["public_key_hex"]
    'handle': handle,
    'registration_sig': registrationSig,
    'nonce': nonce,
  };
}

class AnchoredDid {
  final String did;
  final String handle;
  final String expiresAt;

  const AnchoredDid({
    required this.did,
    required this.handle,
    required this.expiresAt,
  });

  factory AnchoredDid.fromJson(Map<String, dynamic> json) {
    return AnchoredDid(
      did: json['did'] as String,
      handle: json['handle'] as String,
      expiresAt: json['expires_at'] as String,
    );
  }
}

class CreateRecordRequest {
  final String repo;
  final String collection;
  final Map<String, dynamic> record;
  final String commitSig;

  const CreateRecordRequest({
    required this.repo,
    required this.collection,
    required this.record,
    required this.commitSig,
  });

  Map<String, Object?> toJson() => {
    'repo': repo,
    'collection': collection,
    'record': record,
    'commit_sig': commitSig,
  };
}

class CreateRecordResult {
  final String uri;
  final String cid;

  const CreateRecordResult({required this.uri, required this.cid});

  factory CreateRecordResult.fromJson(Map<String, dynamic> json) {
    return CreateRecordResult(
      uri: json['uri'] as String,
      cid: json['cid'] as String,
    );
  }
}

class AtProtoException implements Exception {
  final int statusCode;
  final String error;
  final String? message;

  const AtProtoException({
    required this.statusCode,
    required this.error,
    this.message,
  });

  @override
  String toString() {
    final detail = message == null ? '' : ': $message';
    return 'AtProtoException($statusCode $error$detail)';
  }
}

// ─── Client ──────────────────────────────────────────────────────────────────

class AtProtoClient {
  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  AtProtoClient({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(
         baseUrl ??
             const String.fromEnvironment(
               'ANSIBLE_RELAY_BASE_URL',
               defaultValue: 'http://localhost:4001',
             ),
       ),
       _client = client ?? http.Client();

  /// POST /api/v2/identity/register
  /// Returns [RegistrationChallenge] with {nonce, expires_at}.
  Future<RegistrationChallenge> register({
    required String publicKeyHex,
    required String handleSuffix,
  }) async {
    final body = await _postJson('/api/v2/identity/register', {
      'public_key_hex': publicKeyHex,
      'handle_suffix': handleSuffix,
    });
    return RegistrationChallenge.fromJson(body);
  }

  /// POST /api/v2/identity/anchor
  /// Returns [AnchoredDid] with {did, handle, expires_at}.
  Future<AnchoredDid> anchor(AnchorRequest req) async {
    final body = await _postJson('/api/v2/identity/anchor', req.toJson());
    return AnchoredDid.fromJson(body);
  }

  /// POST /xrpc/com.atproto.repo.createRecord
  /// Returns [CreateRecordResult] with {uri, cid}.
  Future<CreateRecordResult> createRecord(CreateRecordRequest req) async {
    final body = await _postJson(
      '/xrpc/com.atproto.repo.createRecord',
      req.toJson(),
    );
    return CreateRecordResult.fromJson(body);
  }

  /// POST /api/v2/reputation/present
  ///
  /// Submits a W3C Verifiable Presentation to the Relay. On success the Relay
  /// upgrades the holder's reputation tier and returns the new tier string.
  Future<String> presentVp({
    required String holderDid,
    required Map<String, dynamic> vp,
  }) async {
    final body = await _postJson('/api/v2/reputation/present', {
      'holder_did': holderDid,
      'vp': vp,
    });
    return body['reputation_tier'] as String? ?? 'basic';
  }

  /// GET /xrpc/com.atproto.identity.resolveHandle?handle=...
  /// Returns the resolved DID string.
  Future<String> resolveHandle(String handle) async {
    final uri = _endpoint(
      '/xrpc/com.atproto.identity.resolveHandle',
    ).replace(queryParameters: {'handle': handle});

    final response = await _client.get(uri).timeout(timeout);

    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toAtProtoException(response.statusCode, decoded);
    }
    return decoded['did'] as String;
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
      throw _toAtProtoException(response.statusCode, decoded);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Expected JSON object from AT Protocol server');
  }

  AtProtoException _toAtProtoException(
    int statusCode,
    Map<String, dynamic> decoded,
  ) {
    return AtProtoException(
      statusCode: statusCode,
      error: (decoded['error'] as String?) ?? 'unknown_error',
      message: decoded['message'] as String?,
    );
  }

  Uri _endpoint(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }

  void close() {
    _client.close();
  }
}
