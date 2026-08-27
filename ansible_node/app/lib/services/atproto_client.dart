import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/protocol.dart';

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
  final String signingAlgorithm;
  final Map<String, Object?>? genesisCommitment;

  const AnchorRequest({
    required this.did,
    required this.publicKeyHex,
    required this.handle,
    required this.registrationSig,
    required this.nonce,
    this.signingAlgorithm = 'ed25519',
    this.genesisCommitment,
  });

  Map<String, Object?> toJson() => {
    'did': did,
    'public_key_hex':
        publicKeyHex, // must match server params["public_key_hex"]
    'handle': handle,
    'registration_sig': registrationSig,
    'nonce': nonce,
    'signing_algorithm': signingAlgorithm,
    if (genesisCommitment != null) 'genesis_commitment': genesisCommitment,
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

class KeyRotationResult {
  const KeyRotationResult({
    required this.did,
    required this.publicKeyHex,
    required this.signingAlgorithm,
    required this.keyVersion,
  });

  final String did;
  final String publicKeyHex;
  final String signingAlgorithm;
  final int keyVersion;

  factory KeyRotationResult.fromJson(Map<String, dynamic> json) =>
      KeyRotationResult(
        did: json['did'] as String,
        publicKeyHex: json['public_key_hex'] as String,
        signingAlgorithm: json['signing_algorithm'] as String,
        keyVersion: json['key_version'] as int,
      );
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

class RegisteredRelayIdentity {
  final String did;
  final String publicKeyHex;
  final String signingAlgorithm;
  final String handle;

  const RegisteredRelayIdentity({
    required this.did,
    required this.publicKeyHex,
    required this.signingAlgorithm,
    required this.handle,
  });
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
  }) : _baseUri = Uri.parse(baseUrl ?? AppEnvironment.atProtoBaseUrl),
       _client = client ?? http.Client();

  /// POST /api/v2/identity/register
  /// Returns [RegistrationChallenge] with {nonce, expires_at}.
  Future<RegistrationChallenge> register({
    required String publicKeyHex,
    required String handleSuffix,
    String signingAlgorithm = 'ed25519',
  }) async {
    final body = await _postJson('/api/v2/identity/register', {
      'public_key_hex': publicKeyHex,
      'handle_suffix': handleSuffix,
      'signing_algorithm': signingAlgorithm,
    });
    return RegistrationChallenge.fromJson(body);
  }

  /// POST /api/v2/identity/anchor
  /// Returns [AnchoredDid] with {did, handle, expires_at}.
  Future<AnchoredDid> anchor(AnchorRequest req) async {
    final body = await _postJson('/api/v2/identity/anchor', req.toJson());
    return AnchoredDid.fromJson(body);
  }

  /// Reads the Relay's authoritative binding for an already registered DID.
  ///
  /// Returning both the verification key and Relay-local handle lets callers
  /// distinguish an idempotent registration retry from an identity collision.
  Future<RegisteredRelayIdentity?> registeredIdentity(String did) async {
    final encodedDid = Uri.encodeComponent(did);
    final keyResponse = await _client
        .get(
          _endpoint('/api/v1/identity/public-key/$encodedDid'),
          headers: AnsibleProtocol.headers,
        )
        .timeout(timeout);
    final keyBody = _decodeObject(keyResponse.body);
    if (keyResponse.statusCode == 404) return null;
    if (keyResponse.statusCode < 200 || keyResponse.statusCode >= 300) {
      throw _toAtProtoException(keyResponse.statusCode, keyBody);
    }

    final handleResponse = await _client
        .get(
          _endpoint('/api/v1/identity/handle/$encodedDid'),
          headers: AnsibleProtocol.headers,
        )
        .timeout(timeout);
    final handleBody = _decodeObject(handleResponse.body);
    if (handleResponse.statusCode < 200 || handleResponse.statusCode >= 300) {
      throw _toAtProtoException(handleResponse.statusCode, handleBody);
    }

    final resolvedDid = keyBody['did'] as String?;
    final handleDid = handleBody['did'] as String?;
    final publicKeyHex = keyBody['public_key_hex'] as String?;
    final signingAlgorithm = keyBody['signing_algorithm'] as String?;
    final handle = handleBody['handle'] as String?;
    if (resolvedDid != did ||
        handleDid != did ||
        publicKeyHex == null ||
        signingAlgorithm == null ||
        handle == null) {
      throw const FormatException('Invalid registered identity response');
    }
    return RegisteredRelayIdentity(
      did: did,
      publicKeyHex: publicKeyHex,
      signingAlgorithm: signingAlgorithm,
      handle: handle,
    );
  }

  Future<KeyRotationResult> rotateIdentityKey(
    Map<String, Object?> request,
  ) async {
    final body = await _postJson('/api/v2/identity/rotate-key', request);
    return KeyRotationResult.fromJson(body);
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
    Map<String, dynamic>? nostrBinding,
  }) async {
    final body = await _postJson('/api/v2/reputation/present', {
      'holder_did': holderDid,
      'vp': vp,
      if (nostrBinding != null) 'nostr_binding': nostrBinding,
    });
    return body['reputation_tier'] as String? ?? 'basic';
  }

  /// Presents one explicitly selected Wallet VC for a minimal public-profile
  /// badge. The Relay verifies the complete VP but returns only its sanitized
  /// public summary.
  Future<Map<String, dynamic>> presentPublicProfileCredential({
    required String holderDid,
    required Map<String, dynamic> vp,
  }) {
    return _postJson('/api/v2/profile/credentials/present', {
      'holder_did': holderDid,
      'vp': vp,
    });
  }

  /// GET /xrpc/com.atproto.identity.resolveHandle?handle=...
  /// Returns the resolved DID string.
  Future<String> resolveHandle(String handle) async {
    final uri = _endpoint(
      '/xrpc/com.atproto.identity.resolveHandle',
    ).replace(queryParameters: {'handle': handle});

    final response = await _client
        .get(uri, headers: AnsibleProtocol.headers)
        .timeout(timeout);

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
          headers: const {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
          },
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
