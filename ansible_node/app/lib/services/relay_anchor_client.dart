import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/protocol.dart';

/// Typed client for the relay's self-certifying identity-anchor endpoints
/// (recovery design Task 4, relay-side committed). Matches
/// `AnsibleRelay.Web.Controllers.IdentityAnchorController`:
///
///   * POST /api/v1/identity/anchor       — submit an anchor object (+ optional
///       sibling `recovery_proof`).  initial→201 {state:active,anchor_cid};
///       rotation/device_change→200 {state:active,anchor_cid};
///       recovery→202 {state:pending,anchor_cid,grace_until}.
///   * GET  /api/v1/identity/anchor/:did  — the active anchor object, or 404 /
///       423 (frozen).
///   * POST /api/v1/identity/anchor/veto  — {did, pending_anchor_cid, veto_sig}
///       → 200 {state:vetoed,frozen:true}.
///
/// Errors map to [RelayAnchorException] (statusCode + relay error code), which
/// flows through `userFacingError` for friendly bilingual copy.
///
/// On the wire the request body IS the anchor object JSON (body keys + `sig`
/// [+ `device_sig`]), with the optional `recovery_proof` added as a SIBLING key
/// — the relay strips it before computing the canonical body, so it must not be
/// part of [IdentityAnchor.toCanonicalMap]. The canonical body order is
/// produced by the foundation [IdentityAnchor] (matched byte-for-byte to the
/// relay's `@body_keys` / `@device_keys`).
const kDefaultRelayBaseUrl = AppEnvironment.defaultRelayBaseUrl;

/// State of an accepted anchor submission.
enum AnchorState {
  active,
  pending;

  static AnchorState parse(String value) {
    return switch (value) {
      'active' => AnchorState.active,
      'pending' => AnchorState.pending,
      _ => throw FormatException('Unknown anchor state: $value'),
    };
  }
}

/// Result of POST /api/v1/identity/anchor.
class AnchorSubmitResult {
  final AnchorState state;
  final String anchorCid;

  /// Set only for recovery (pending) submissions — when the grace window ends.
  final DateTime? graceUntil;

  /// HTTP status the relay returned (201 initial, 200 rotation/device_change,
  /// 202 recovery-pending).
  final int statusCode;

  const AnchorSubmitResult({
    required this.state,
    required this.anchorCid,
    required this.statusCode,
    this.graceUntil,
  });

  bool get isPending => state == AnchorState.pending;
}

/// Typed exception for relay anchor failures (401/409/422/423 + network).
class RelayAnchorException implements Exception {
  final int statusCode;
  final String? error;
  final String responseBody;

  const RelayAnchorException({
    required this.statusCode,
    required this.responseBody,
    this.error,
  });

  @override
  String toString() =>
      'RelayAnchorException($statusCode ${error ?? 'relay_anchor_error'})';
}

class RelayAnchorClient {
  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  RelayAnchorClient({
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  })  : baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client();

  /// Submits [anchor] to the relay. When [recoveryProof] is non-null it is sent
  /// as the sibling `recovery_proof` field (the enrolled device-key signature
  /// over the canonical body) — required for `recovery` re-anchors.
  Future<AnchorSubmitResult> submitAnchor(
    IdentityAnchor anchor, {
    String? recoveryProof,
  }) async {
    final payload = <String, Object?>{
      ...anchor.toCanonicalMap(),
      if (recoveryProof != null) 'recovery_proof': recoveryProof,
    };

    final response = await _post('/api/v1/identity/anchor', payload);
    final decoded = _decodeObject(response);

    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 202) {
      final graceRaw = decoded['grace_until'];
      return AnchorSubmitResult(
        state: AnchorState.parse(decoded['state'] as String),
        anchorCid: decoded['anchor_cid'] as String,
        statusCode: response.statusCode,
        graceUntil: graceRaw is String ? DateTime.tryParse(graceRaw) : null,
      );
    }
    throw _toException(response, decoded);
  }

  /// GET the active anchor object for [did]. Returns null on 404
  /// (no anchor yet). Throws [RelayAnchorException] on 423 (frozen) / others.
  Future<IdentityAnchor?> fetchActiveAnchor(String did) async {
    final response = await _client
        .get(
          _endpoint('/api/v1/identity/anchor/${Uri.encodeComponent(did)}'),
          headers: AnsibleProtocol.headers,
        )
        .timeout(timeout);

    if (response.statusCode == 404) return null;
    if (response.statusCode == 200) {
      final decoded = _decodeObject(response);
      return IdentityAnchor.fromMap(decoded);
    }
    throw _toException(response, _tryDecode(response));
  }

  /// POST a veto for a pending recovery anchor. [vetoSig] is a hex Ed25519
  /// signature over the pending anchor's canonical body, by any
  /// previously-enrolled identity or device key of the DID. The relay freezes
  /// the account on success.
  Future<void> vetoPendingAnchor({
    required String did,
    required String pendingAnchorCid,
    required String vetoSig,
  }) async {
    final response = await _post('/api/v1/identity/anchor/veto', {
      'did': did,
      'pending_anchor_cid': pendingAnchorCid,
      'veto_sig': vetoSig,
    });
    if (response.statusCode == 200) return;
    throw _toException(response, _tryDecode(response));
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) {
    return _client
        .post(
          _endpoint(path),
          headers: const {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Expected JSON object from relay: ${response.body}');
  }

  Map<String, dynamic> _tryDecode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  RelayAnchorException _toException(
    http.Response response,
    Map<String, dynamic> decoded,
  ) {
    return RelayAnchorException(
      statusCode: response.statusCode,
      responseBody: response.body,
      error: decoded['error'] as String?,
    );
  }

  Uri _endpoint(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$path');
  }

  void close() => _client.close();
}
