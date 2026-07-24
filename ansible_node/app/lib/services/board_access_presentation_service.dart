import 'dart:convert';
import 'dart:math';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'credential_payload_codec.dart';
import 'oid4vci_wallet_client.dart';
import 'wallet_holder_key_service.dart';

class BoardAccessException implements Exception {
  const BoardAccessException(this.code, {this.statusCode});
  final String code;
  final int? statusCode;
}

class BoardAccessCapability {
  const BoardAccessCapability({
    required this.token,
    required this.forumHostId,
    required this.boardId,
    required this.host,
    required this.scopes,
    required this.expiresAt,
    required this.policyVersion,
  });

  final String token;
  final String forumHostId;
  final String boardId;
  final Uri host;
  final List<String> scopes;
  final DateTime expiresAt;
  final int policyVersion;
}

class _BoardCredential {
  const _BoardCredential({
    required this.holderDid,
    this.compactJwt,
    this.dataIntegrityCredential,
  });

  final String holderDid;
  final String? compactJwt;
  final Map<String, Object?>? dataIntegrityCredential;
}

class BoardAccessPresentationService {
  BoardAccessPresentationService({
    required WalletRepository walletRepository,
    http.Client? httpClient,
    SecureCredentialPayloadCodec? payloadCodec,
    HolderBindingKey? holderKey,
    DidSigner? didSigner,
    DateTime Function()? now,
  }) : _wallet = walletRepository,
       _http = httpClient ?? http.Client(),
       _codec = payloadCodec ?? const SecureCredentialPayloadCodec(),
       _holderKeyOverride = holderKey,
       _didSigner = didSigner ?? DidSignerImpl(),
       _now = now ?? (() => DateTime.now().toUtc());

  final WalletRepository _wallet;
  final http.Client _http;
  final SecureCredentialPayloadCodec _codec;
  final HolderBindingKey? _holderKeyOverride;
  final DidSigner _didSigner;
  final DateTime Function() _now;

  HardwareHolderJwtSigner _signerForBoard(String forumHostId, String boardId) =>
      HardwareHolderJwtSigner(
        key:
            _holderKeyOverride ??
            BoardHolderKeyService(boardId: '$forumHostId\u0000$boardId'),
      );

  Future<String> pairwiseSubject(String forumHostId, String boardId) =>
      _signerForBoard(forumHostId, boardId).pairwiseDid();

  /// Returns whether the local wallet can satisfy [action] without contacting
  /// the Forum Host. This is UX pre-validation only; the Forum Host always
  /// re-evaluates the live credential status when issuing a capability.
  Future<bool> canAuthorizeLocally({
    required Map<String, Object?> policy,
    required String forumHostId,
    required String boardId,
    required String action,
  }) async {
    final actionPolicy = policy[action];
    if (actionPolicy is! Map || actionPolicy['requirement'] is! String) {
      return false;
    }
    final requirement = actionPolicy['requirement'] as String;
    if (requirement == 'public' || requirement == 'posting_policy') {
      return true;
    }
    if (requirement == 'board_moderator') return false;
    try {
      final credential = await _membershipCredentialForPolicy(
        policy: policy,
        action: action,
        forumHostId: forumHostId,
        boardId: boardId,
      );
      return credential.compactJwt == null ||
          credential.holderDid ==
              await _signerForBoard(forumHostId, boardId).pairwiseDid();
    } on BoardAccessException {
      return false;
    }
  }

  Future<BoardAccessCapability> authorize({
    required Uri forumHost,
    required String boardId,
    required String action,
  }) async {
    final base = forumHost.resolve('/api/v1/forum-host/boards/$boardId');
    final requirements = _json(
      await _http.get(base.resolve('${base.path}/access-requirements')),
    );
    final forumHostId = _string(requirements, 'forum_host_id');
    if (_string(requirements, 'board_id') != boardId) {
      throw const BoardAccessException('invalid_board_scope');
    }
    final signer = _signerForBoard(forumHostId, boardId);
    final audience = _string(requirements, 'host');
    final options = _json(
      await _http.post(
        base.resolve('${base.path}/presentation/options'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'action': action}),
      ),
    );
    final nonce = _string(options, 'nonce');
    final state = _string(options, 'state');
    final credential = await _membershipCredential(
      requirements: requirements,
      action: action,
      forumHostId: forumHostId,
      boardId: boardId,
    );
    final vpToken = credential.compactJwt != null
        ? await _hostedMembershipVp(
            signer: signer,
            credential: credential,
            audience: audience,
            nonce: nonce,
          )
        : await _dataIntegrityVp(
            signer: signer,
            credential: credential,
            audience: audience,
            nonce: nonce,
          );
    final response = _json(
      await _http.post(
        base.resolve('${base.path}/presentation/verify'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'state': state,
          'vp_token': vpToken,
        }),
      ),
    );
    final scopes = response['scopes'];
    if (scopes is! List || !scopes.every((value) => value is String)) {
      throw const BoardAccessException('invalid_capability_response');
    }
    return BoardAccessCapability(
      token: _string(response, 'board_capability'),
      forumHostId: forumHostId,
      boardId: boardId,
      host: forumHost,
      scopes: scopes.cast<String>(),
      expiresAt: DateTime.parse(_string(response, 'expires_at')).toUtc(),
      policyVersion: response['policy_version'] as int,
    );
  }

  Future<Map<String, String>> proofHeaders({
    required BoardAccessCapability capability,
    required String method,
    required Uri requestUri,
    required String scope,
  }) async {
    if (!capability.expiresAt.isAfter(_now()) ||
        !capability.scopes.contains(scope)) {
      throw const BoardAccessException('capability_expired');
    }
    final timestamp = (_now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _randomNonce();
    final tokenHash = sha256.convert(utf8.encode(capability.token)).toString();
    final canonical = [
      method.toUpperCase(),
      requestUri.path,
      capability.boardId,
      scope,
      timestamp,
      nonce,
      tokenHash,
    ].join('\n');
    final signer = _signerForBoard(capability.forumHostId, capability.boardId);
    return {
      'x-elix-board-capability': capability.token,
      'x-elix-board-jwk': await signer.encodedJwk(),
      'x-elix-board-timestamp': timestamp,
      'x-elix-board-request-nonce': nonce,
      'x-elix-board-proof': await signer.signRequest(canonical),
    };
  }

  Future<Object> _hostedMembershipVp({
    required HardwareHolderJwtSigner signer,
    required _BoardCredential credential,
    required String audience,
    required String nonce,
  }) async {
    final holder = await signer.pairwiseDid();
    if (credential.holderDid != holder) {
      throw const BoardAccessException('holder_binding_failed');
    }
    return signer.signJwt(
      typ: 'openid4vp+jwt',
      claims: {
        'aud': audience,
        'nonce': nonce,
        'iat': _now().millisecondsSinceEpoch ~/ 1000,
        'sub': holder,
        'vp': {
          'verifiableCredential': [credential.compactJwt],
        },
      },
    );
  }

  Future<Object> _dataIntegrityVp({
    required HardwareHolderJwtSigner signer,
    required _BoardCredential credential,
    required String audience,
    required String nonce,
  }) async {
    final raw = credential.dataIntegrityCredential;
    if (raw == null) throw const BoardAccessException('invalid_credential');
    final parsed = TrisAuraCredential.fromJson(raw);
    final unsigned = VpBuilder.buildUnsigned(
      credential: parsed,
      holderDid: credential.holderDid,
      nonce: nonce,
      audience: audience,
      createdAt: _now(),
    );
    unsigned['deviceKeyJwk'] =
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(await signer.encodedJwk()),
                ),
              ),
            )
            as Map<String, dynamic>;
    final canonical = VpBuilder.canonicalPayload(unsigned);
    final signature = await _didSigner.sign(utf8.encode(canonical));
    return VpBuilder.addProof(
      unsignedPresentation: unsigned,
      proofValue: signature.hex,
    );
  }

  Future<_BoardCredential> _membershipCredential({
    required Map<String, Object?> requirements,
    required String action,
    required String forumHostId,
    required String boardId,
  }) async {
    final policy = requirements['policy'];
    if (policy is! Map) throw const BoardAccessException('invalid_response');
    return _membershipCredentialForPolicy(
      policy: Map<String, Object?>.from(policy),
      action: action,
      forumHostId: forumHostId,
      boardId: boardId,
    );
  }

  Future<_BoardCredential> _membershipCredentialForPolicy({
    required Map<String, Object?> policy,
    required String action,
    required String forumHostId,
    required String boardId,
  }) async {
    final rule = _credentialRule(policy, action);
    final credentialType = rule['credential_type'];
    if (credentialType is! String || credentialType.isEmpty) {
      throw const BoardAccessException('invalid_response');
    }
    for (final metadata in await _wallet.listCredentials()) {
      if (metadata.credentialType != credentialType ||
          metadata.status != WalletCredentialStatus.active ||
          !metadata.validUntil.isAfter(_now())) {
        continue;
      }
      final payload = await _wallet.getEncryptedPayload(metadata.credentialId);
      if (payload == null) {
        continue;
      }
      final decoded = await _codec.decode(payload);
      if (decoded['format'] == 'jwt_vc_json' &&
          decoded['forum_host_id'] == forumHostId &&
          decoded['board_id'] == boardId &&
          decoded['compact'] is String &&
          decoded['vc'] is Map &&
          _credentialSatisfies(
            Map<String, Object?>.from(decoded['vc'] as Map),
            rule,
            forumHostId,
            boardId,
          )) {
        return _BoardCredential(
          holderDid: metadata.holderDid,
          compactJwt: decoded['compact'] as String,
        );
      }
      if (_credentialSatisfies(decoded, rule, forumHostId, boardId)) {
        return _BoardCredential(
          holderDid: metadata.holderDid,
          dataIntegrityCredential: decoded,
        );
      }
    }
    throw const BoardAccessException('no_matching_credential');
  }

  Map<String, Object?> _credentialRule(
    Map<String, Object?> policy,
    String action,
  ) {
    final actionPolicy = policy[action];
    if (actionPolicy is! Map || actionPolicy['requirement'] is! String) {
      throw const BoardAccessException('invalid_response');
    }
    final rules = policy['requirements'];
    final rule = rules is Map ? rules[actionPolicy['requirement']] : null;
    if (rule is! Map) throw const BoardAccessException('invalid_response');
    return Map<String, Object?>.from(rule);
  }

  bool _credentialSatisfies(
    Map<String, Object?> vc,
    Map<String, Object?> rule,
    String forumHostId,
    String boardId,
  ) {
    final types = vc['type'];
    if (types is! List || !types.contains(rule['credential_type'])) {
      return false;
    }
    final trusted = rule['trusted_issuers'];
    if (trusted is! List || !trusted.contains(vc['issuer'])) return false;
    final credentialConfigurationId = rule['credential_configuration_id'];
    if (credentialConfigurationId != null &&
        vc['credentialConfigurationId'] != credentialConfigurationId &&
        _claimAtPath(vc, 'credential_configuration_id') !=
            credentialConfigurationId) {
      return false;
    }
    final credentialBoardId = _claimAtPath(vc, 'board_id');
    final credentialForumHostId = _claimAtPath(vc, 'forum_host_id');
    // Board-scoped membership credentials are bound to both dimensions.  A
    // board policy may also accept a generic VC (for example citizenship),
    // which deliberately has neither claim.
    if (credentialForumHostId != null || credentialBoardId != null) {
      if (credentialForumHostId != forumHostId ||
          credentialBoardId != boardId) {
        return false;
      }
    }
    final claims = rule['claims'];
    if (claims is! List) return false;
    for (final rawClaim in claims) {
      if (rawClaim is! Map || rawClaim['op'] != 'equals') return false;
      if (_claimAtPath(vc, rawClaim['path']) != rawClaim['value']) return false;
    }
    return true;
  }

  Object? _claimAtPath(Map<String, Object?> vc, Object? path) {
    if (path is! String || path.isEmpty) return null;
    final normalized = path.startsWith('credentialSubject.')
        ? path
        : 'credentialSubject.$path';
    Object? value = vc;
    for (final segment in normalized.split('.')) {
      if (value is! Map || !value.containsKey(segment)) return null;
      value = value[segment];
    }
    return value;
  }

  Map<String, Object?> _json(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map) {
      throw BoardAccessException(
        decoded is Map
            ? decoded['error']?.toString() ?? 'request_failed'
            : 'invalid_response',
        statusCode: response.statusCode,
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  String _string(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is String && result.isNotEmpty) return result;
    throw const BoardAccessException('invalid_response');
  }

  String _randomNonce() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
