import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

import '../config/protocol.dart';
import 'issuer_attestation_service.dart';
import 'legacy_identity_key_resolver.dart';
import 'notification_projector.dart';
import 'private_board_crypto_service.dart';
import 'op_signature_payload.dart';
import 'relay_identity_client.dart';
import 'self_backfill_state_store.dart';

typedef RemoteOpEd25519Verifier =
    Future<bool> Function({
      required String publicKeyHex,
      required List<int> message,
      required String signatureHex,
    });

typedef LegacyLocalPublicKeyResolver = Future<String?> Function(String did);

typedef BoardReadAuthorization =
    Future<Map<String, String>> Function(
      HostedBoardProjection board,
      Uri requestUri,
    );

typedef BoardWriteAuthorization =
    Future<Map<String, String>> Function(
      HostedBoardProjection board,
      Uri requestUri,
    );

/// Compatibility client for the legacy board delta endpoint.
///
/// V1.1+ will move board synchronization to signed Ops, but this client keeps
/// the existing Sync Settings workflow functional while retention controls are
/// enforced locally.
class RelayApiClient {
  final String baseUrl;
  final http.Client _client;
  String? _accessToken;

  RelayApiClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: const {
        'content-type': 'application/json',
        ...AnsibleProtocol.headers,
      },
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Relay authentication failed: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDelta({int? cursor, int limit = 100}) async {
    final query = {
      if (cursor != null) 'cursor': cursor.toString(),
      'limit': limit.toString(),
    };
    final uri = Uri.parse(
      '$baseUrl/api/v1/ops/delta',
    ).replace(queryParameters: query);
    final response = await _client.get(uri, headers: authHeaders);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Relay delta failed: ${response.statusCode}');
    }

    final body = _decodeResponseObject(response, operation: 'Relay delta');
    return _normalizeDelta(body);
  }

  Future<Map<String, dynamic>> getBoardDelta({
    required String boardId,
    required Map<String, String> proofHeaders,
    int? cursor,
    int limit = 100,
  }) async {
    final uri =
        Uri.parse(
          '$baseUrl/api/v1/forum-host/boards/${Uri.encodeComponent(boardId)}/ops/delta',
        ).replace(
          queryParameters: {
            if (cursor != null) 'cursor': cursor.toString(),
            'limit': limit.toString(),
          },
        );
    final response = await _client.get(
      uri,
      headers: {...authHeaders, ...proofHeaders},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Board delta failed: ${response.statusCode}');
    }
    return _normalizeDelta(
      _decodeResponseObject(response, operation: 'Board delta'),
    );
  }

  Map<String, dynamic> _decodeResponseObject(
    http.Response response, {
    required String operation,
  }) {
    if (response.body.trim().isEmpty) {
      throw StateError('$operation returned an empty response');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw FormatException('$operation returned a non-object response');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, String> get authHeaders {
    final token = _accessToken;
    return {
      ...AnsibleProtocol.headers,
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _normalizeDelta(Map<String, dynamic> body) {
    final ops = body['ops'];
    if (ops is! List<dynamic>) return body;

    return {
      'activities': ops
          .whereType<Map>()
          .map((op) => Map<String, dynamic>.from(op))
          .where(_isKnownSchemaVersion)
          .map(_opToActivityLogEntry)
          .toList(),
      'nextCursor': body['next_cursor'] ?? body['nextCursor'] ?? 0,
      'hasMore': body['has_more'] ?? body['hasMore'] ?? false,
    };
  }

  /// Phase 0 — API versioning: ops authored with a newer payload format than
  /// this build understands are skipped (with a log) instead of being
  /// misparsed into corrupt local rows. Absent/odd values mean version 1
  /// (legacy relays).
  bool _isKnownSchemaVersion(Map<String, dynamic> op) {
    final schemaVersion = op['schema_version'] ?? op['schemaVersion'];
    if (schemaVersion is num &&
        schemaVersion > AnsibleProtocol.currentVersion) {
      developer.log(
        'Skipping op ${op['op_id']} with unknown schema_version '
        '$schemaVersion (this app speaks ${AnsibleProtocol.currentVersion})',
        name: 'RelayApiClient',
      );
      return false;
    }
    return true;
  }

  Map<String, dynamic> _opToActivityLogEntry(Map<String, dynamic> op) {
    final payload = _decodePayload(op['payload'] as String?);
    final entityType = op['entity_type'] as String? ?? '';
    final entityId = op['entity_id'] as String? ?? '';
    final opId = op['op_id'] as String? ?? entityId;
    final receivedAt =
        op['received_at'] as String? ??
        DateTime.now().toUtc().toIso8601String();

    return {
      'logId': op['log_id'] as int? ?? 0,
      'signedOp': {
        'opId': opId,
        'authorDid': op['author_did'] as String? ?? '',
        'entityType': entityType,
        'entityId': entityId,
        'opType': op['op_type'] as String? ?? '',
        'payload': op['payload'] as String? ?? '',
        'signature': op['signature'] as String? ?? '',
        'publicKeyHex':
            (op['public_key_hex'] as String?) ??
            (op['publicKeyHex'] as String?),
        'reputationTier':
            (op['reputation_tier'] as String?) ??
            (op['reputationTier'] as String?),
      },
      'activity': {
        'activityId': opId,
        'type': _activityType(op['op_type'] as String?),
        'entityType': entityType,
        'entityId': entityId,
        'boardId': payload['boardId'],
        'threadId': payload['threadId'],
        'authorId': op['author_did'] as String? ?? '',
        'createdAt': payload['createdAt'] as String? ?? receivedAt,
        'payload': payload,
      },
    };
  }

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return {};
    try {
      return jsonDecode(utf8.decode(base64Decode(payload)))
          as Map<String, dynamic>;
    } catch (_) {
      // Web publication records created before the shared Relay reaction
      // encoder stored JSON directly. Read them without losing their routing
      // fields while current writes remain base64 JSON.
      try {
        return jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        return {'rawPayload': payload};
      }
    }
  }

  String _activityType(String? opType) {
    return switch (opType) {
      'insert' => 'create',
      'update' || 'crdt_merge' => 'update',
      'delete' => 'delete',
      _ => opType ?? 'update',
    };
  }
}

class RemoteOpSignatureVerifier {
  final RemoteOpEd25519Verifier _verify;
  final Future<String?> Function(String did)? _resolvePublicKey;
  final String? _localDid;
  final LegacyLocalPublicKeyResolver? _resolveLegacyLocalPublicKey;
  // Simple in-memory cache: did → verified public key hex
  final Map<String, String> _keyCache = {};

  RemoteOpSignatureVerifier({
    RemoteOpEd25519Verifier? verify,
    Future<String?> Function(String did)? resolvePublicKey,
    String? localDid,
    LegacyLocalPublicKeyResolver? resolveLegacyLocalPublicKey,
  }) : _verify = verify ?? _verifyWithDidSigner,
       _resolvePublicKey = resolvePublicKey,
       _localDid = localDid,
       _resolveLegacyLocalPublicKey = resolveLegacyLocalPublicKey;

  Future<bool> isTrusted(Map<String, dynamic> entry) async {
    final signedOp = _signedOp(entry);
    if (signedOp == null) return false;

    final opId = _string(signedOp, 'opId');
    final authorDid = _string(signedOp, 'authorDid');
    final entityType = _string(signedOp, 'entityType');
    final entityId = _string(signedOp, 'entityId');
    final opType = _string(signedOp, 'opType');
    final payload = _string(signedOp, 'payload');
    final signature = _string(signedOp, 'signature');
    final publicKeyHex = _string(signedOp, 'publicKeyHex');
    if ([
      opId,
      authorDid,
      entityType,
      entityId,
      opType,
      payload,
      signature,
      publicKeyHex,
    ].any((value) => value == null || value.isEmpty)) {
      return false;
    }
    final isEd25519 = _isHex(publicKeyHex!, 64) && _isHex(signature!, 128);
    final isP256 =
        _isHex(publicKeyHex, 130) &&
        publicKeyHex.startsWith('04') &&
        (RegExp(r'^[0-9a-fA-F]{128}$').hasMatch(signature!) ||
            RegExp(r'^[0-9a-fA-F]{136,144}$').hasMatch(signature));
    if (!isEd25519 && !isP256) {
      return false;
    }
    if (!_matchesActivity(entry, signedOp)) {
      return false;
    }

    final signingPayload = OpSignaturePayload.fromFields(
      opId: opId!,
      authorDid: authorDid!,
      entityType: entityType!,
      entityId: entityId!,
      opType: opType!,
      payload: payload!,
    );
    final verificationSignature = isP256 && signature.length == 128
        ? _rawP256SignatureToDer(signature)
        : signature;
    var verifiedPublicKey = publicKeyHex;
    var signatureValid = await _verify(
      publicKeyHex: publicKeyHex,
      message: utf8.encode(signingPayload),
      signatureHex: verificationSignature,
    );
    String? legacyLocalKey;
    if (!signatureValid &&
        authorDid == _localDid &&
        _resolveLegacyLocalPublicKey != null &&
        _isHex(signature, 128)) {
      legacyLocalKey = await _resolveLegacyLocalPublicKey(authorDid);
      if (legacyLocalKey != null && _isHex(legacyLocalKey, 64)) {
        signatureValid = await _verify(
          publicKeyHex: legacyLocalKey,
          message: utf8.encode(signingPayload),
          signatureHex: signature,
        );
        if (signatureValid) verifiedPublicKey = legacyLocalKey;
      }
    }
    if (!signatureValid) return false;

    // Verify the public key is bound to authorDid (prevents relay from re-signing under arbitrary DIDs)
    final resolveKey = _resolvePublicKey;
    if (resolveKey != null) {
      final authorizedKey = _keyCache[authorDid] ?? await resolveKey(authorDid);
      if (authorizedKey == null) return false; // DID not registered
      final isAuthorizedCurrentKey =
          authorizedKey.toLowerCase() == verifiedPublicKey.toLowerCase();
      final isSelfCertifiedLegacyKey =
          legacyLocalKey != null &&
          legacyLocalKey.toLowerCase() == verifiedPublicKey.toLowerCase();
      if (!isAuthorizedCurrentKey && !isSelfCertifiedLegacyKey) {
        return false; // Key mismatch
      }
      _cacheKey(authorDid, authorizedKey); // Cache hit for future ops
    }

    return true;
  }

  void _cacheKey(String did, String keyHex) {
    if (_keyCache.length >= 500) {
      _keyCache.remove(_keyCache.keys.first);
    }
    _keyCache[did] = keyHex;
  }

  Map<String, dynamic>? _signedOp(Map<String, dynamic> entry) {
    final raw = entry['signedOp'] ?? entry['signed_op'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String? _string(Map<String, dynamic> value, String key) {
    final raw = value[key] ?? value[_snakeCase(key)];
    if (raw is String) return raw;
    return null;
  }

  bool _matchesActivity(
    Map<String, dynamic> entry,
    Map<String, dynamic> signedOp,
  ) {
    final rawActivity = entry['activity'];
    if (rawActivity is! Map) return false;
    final activity = Map<String, dynamic>.from(rawActivity);
    return activity['activityId'] == _string(signedOp, 'opId') &&
        activity['authorId'] == _string(signedOp, 'authorDid') &&
        activity['entityType'] == _string(signedOp, 'entityType') &&
        activity['entityId'] == _string(signedOp, 'entityId') &&
        activity['type'] == _activityType(_string(signedOp, 'opType'));
  }

  bool _isHex(String value, int expectedLength) {
    if (value.length != expectedLength) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  /// Converts the fixed-width IEEE P1363 P-256 form (`r || s`) used by early
  /// Relay ops into the ASN.1 DER form expected by CryptoKit. Both encodings
  /// represent the same ECDSA signature; no trust decision is weakened.
  String _rawP256SignatureToDer(String rawHex) {
    List<int> integerBytes(String value) {
      final bytes = <int>[
        for (var i = 0; i < value.length; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ];
      while (bytes.length > 1 && bytes.first == 0) {
        bytes.removeAt(0);
      }
      if ((bytes.first & 0x80) != 0) bytes.insert(0, 0);
      return bytes;
    }

    final r = integerBytes(rawHex.substring(0, 64));
    final s = integerBytes(rawHex.substring(64));
    final sequence = <int>[0x02, r.length, ...r, 0x02, s.length, ...s];
    return <int>[
      0x30,
      sequence.length,
      ...sequence,
    ].map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  String _snakeCase(String key) {
    return key.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  String _activityType(String? opType) {
    return switch (opType) {
      'insert' => 'create',
      'update' || 'crdt_merge' => 'update',
      'delete' => 'delete',
      _ => opType ?? 'update',
    };
  }

  static Future<bool> _verifyWithDidSigner({
    required String publicKeyHex,
    required List<int> message,
    required String signatureHex,
  }) {
    return DidSigner.verify(
      publicKeyHex: publicKeyHex,
      message: message,
      signature: Ed25519Signature(signatureHex),
    );
  }
}

class RemoteSyncService {
  final RemoteNodeRepository _remoteNodeRepo;
  final BoardSyncConfigRepository _boardSyncConfigRepo;
  final HostedBoardRepository? _hostedBoardRepo;
  final BoardRepository _boardRepo;
  final ThreadRepository _threadRepo;
  final PostRepository _postRepo;
  final ReactionRepository? _reactionRepo;
  // Optional follow-aware ingestion: when a follow repository and the local
  // follower DID are provided, ops authored by followed users are retained even
  // when their board is not synced, and standalone murmur/note ops are folded
  // into the content item store. Null preserves the legacy board-only behavior.
  final FollowRepository? _followRepo;
  final ContentItemRepository? _contentItemRepo;
  final DidReputationRepository? _didReputationRepo;
  final String? _followerDid;
  // Optional local notification projection (Phase A): folds trusted incoming
  // ops into the local notifications table. Pure local projection — adds no
  // server request and runs before board filtering so follow ops (which have
  // no board) still notify.
  final NotificationProjector? _notificationProjector;
  final RemoteTombstoneRepository? _remoteTombstones;

  // Portable issuer re-verification (federation trust): the ONLY source of
  // reputation tiers on ingest. Null keeps tiers untouched (everyone basic).
  final IssuerAttestationService? _issuerAttestations;
  final RemoteOpSignatureVerifier _opSignatureVerifier;
  final BoardReadAuthorization? _authorizeBoardRead;
  final PrivateBoardCryptoService _privateBoardCrypto;
  final DateTime Function() _now;
  final SelfBackfillStateStore _selfBackfillState;

  RemoteSyncService({
    required RemoteNodeRepository remoteNodeRepo,
    required BoardSyncConfigRepository boardSyncConfigRepo,
    HostedBoardRepository? hostedBoardRepo,
    required BoardRepository boardRepo,
    required ThreadRepository threadRepo,
    required PostRepository postRepo,
    ReactionRepository? reactionRepository,
    FollowRepository? followRepository,
    ContentItemRepository? contentItemRepo,
    DidReputationRepository? didReputationRepo,
    String? followerDid,
    NotificationProjector? notificationProjector,
    RemoteTombstoneRepository? remoteTombstoneRepository,
    IssuerAttestationService? issuerAttestationService,
    RemoteOpSignatureVerifier? opSignatureVerifier,
    RelayIdentityClient? identityClient,
    BoardReadAuthorization? authorizeBoardRead,
    PrivateBoardCryptoService? privateBoardCrypto,
    SelfBackfillStateStore selfBackfillState =
        const CompletedSelfBackfillStateStore(),
    DateTime Function()? now,
  }) : _remoteNodeRepo = remoteNodeRepo,
       _boardSyncConfigRepo = boardSyncConfigRepo,
       _hostedBoardRepo = hostedBoardRepo,
       _boardRepo = boardRepo,
       _threadRepo = threadRepo,
       _postRepo = postRepo,
       _reactionRepo = reactionRepository,
       _followRepo = followRepository,
       _contentItemRepo = contentItemRepo,
       _didReputationRepo = didReputationRepo,
       _followerDid = followerDid,
       _notificationProjector = notificationProjector,
       _remoteTombstones = remoteTombstoneRepository,
       _issuerAttestations = issuerAttestationService,
       _opSignatureVerifier =
           opSignatureVerifier ??
           RemoteOpSignatureVerifier(
             resolvePublicKey: identityClient != null
                 ? (did) => identityClient.fetchPublicKey(did)
                 : null,
             localDid: followerDid,
             resolveLegacyLocalPublicKey: followerDid != null
                 ? LegacyIdentityKeyResolver().resolve
                 : null,
           ),
       _authorizeBoardRead = authorizeBoardRead,
       _privateBoardCrypto = privateBoardCrypto ?? PrivateBoardCryptoService(),
       _selfBackfillState = selfBackfillState,
       _now = now ?? DateTime.now;

  Future<SyncResult> syncFromNode(
    RelayApiClient remoteClient,
    RemoteNode remoteNode, {
    bool requireBoardSyncConfig = true,
  }) async {
    try {
      final enabledConfigs = await _boardSyncConfigRepo.listEnabledByRemote(
        remoteNode.id,
      );
      final hostedSubscriptions =
          (await _hostedBoardRepo?.listSubscriptions(
                    forumHostId: remoteNode.id,
                  ) ??
                  const <BoardSubscription>[])
              .where((subscription) => subscription.readEnabled)
              .toList();
      final hostedProjections =
          await _hostedBoardRepo?.listProjections(forumHostId: remoteNode.id) ??
          const <HostedBoardProjection>[];
      final hostedProjectionByBoardId = {
        for (final projection in hostedProjections)
          projection.hostedBoardId: projection,
      };
      final protectedHostedBoardIds = {
        for (final projection in hostedProjections)
          if (_requiresBoardCapability(projection)) projection.hostedBoardId,
      };
      final publicHostedSubscriptions = hostedSubscriptions
          .where(
            (subscription) =>
                !protectedHostedBoardIds.contains(subscription.hostedBoardId),
          )
          .toList();
      final protectedHostedSubscriptions = hostedSubscriptions
          .where(
            (subscription) =>
                protectedHostedBoardIds.contains(subscription.hostedBoardId),
          )
          .toList();
      final hostedSubscriptionByBoardId = {
        for (final subscription in hostedSubscriptions)
          subscription.hostedBoardId: subscription,
      };
      final enabledBoardIdSet = enabledConfigs.map((c) => c.boardId).toSet();
      final followedAuthorDids = await _resolveFollowedAuthorDids();
      final localDid = _followerDid?.trim();
      final needsSelfBackfill =
          localDid != null &&
          localDid.isNotEmpty &&
          !await _selfBackfillState.isComplete(
            remoteNodeId: remoteNode.id,
            did: localDid,
          );
      if (requireBoardSyncConfig &&
          enabledBoardIdSet.isEmpty &&
          hostedSubscriptions.isEmpty &&
          followedAuthorDids.isEmpty &&
          !needsSelfBackfill) {
        return SyncResult.success(
          activitiesProcessed: 0,
          newCursor: remoteNode.syncCursor,
        );
      }
      final retentionDaysByBoard = {
        for (final config in enabledConfigs)
          config.boardId: config.retentionDays,
      };

      int totalProcessed = 0;
      // A newly-created hosted-board subscription can legitimately lag behind
      // the node-wide cursor. Start at the oldest active subscription cursor so
      // its history is replayed instead of being skipped forever.
      int currentCursor = publicHostedSubscriptions.fold(
        needsSelfBackfill ? 0 : remoteNode.syncCursor,
        (oldest, subscription) =>
            subscription.syncCursor < oldest ? subscription.syncCursor : oldest,
      );
      bool hasMore = true;
      final syncTime = _now();

      while (hasMore) {
        final deltaJson = await remoteClient.getDelta(
          cursor: currentCursor > 0 ? currentCursor : null,
          limit: 100,
        );
        final trusted = await _trustedActivities(deltaJson);
        await _captureAuthorTiers(trusted);
        final delta = DeltaResponse.fromJson({
          ...deltaJson,
          'activities': trusted,
        });

        for (final entry in delta.activities) {
          // Local notification projection first: replies to the local user's
          // threads/posts and follows targeting the local DID must notify even
          // when the op is filtered out below (e.g. follow ops have no board).
          // Dedup-keyed, so re-synced ops never duplicate.
          await _notificationProjector?.onSyncedActivity(entry.activity);
          final hostedRoute = _routeHostedActivity(
            entry.activity,
            hostedSubscriptionByBoardId,
            hostedProjectionByBoardId,
          );
          final boardId = entry.activity.boardId;
          final allowedByLegacy =
              boardId != null && enabledBoardIdSet.contains(boardId);
          final allowedByFollowedAuthor = followedAuthorDids.contains(
            entry.activity.authorId,
          );
          final allowedBySelf =
              localDid != null && entry.activity.authorId == localDid;
          final allowedByReactionBoard =
              entry.activity.entityType.toLowerCase() == 'reaction' &&
              enabledBoardIdSet.contains(entry.activity.boardId);
          if (requireBoardSyncConfig &&
              !allowedByLegacy &&
              hostedRoute == null &&
              !allowedByFollowedAuthor &&
              !allowedBySelf &&
              !allowedByReactionBoard) {
            continue;
          }
          final activity = hostedRoute?.activity ?? entry.activity;
          final retentionDays =
              hostedRoute?.subscription.retentionDays ??
              retentionDaysByBoard[activity.boardId ?? boardId];
          if (!_isWithinRetention(activity, retentionDays, syncTime)) {
            continue;
          }

          // A followed-author op whose board is not synced has no local
          // board/thread context; create lightweight stubs so the post/thread is
          // storable and renderable. Standalone murmur/note need no context.
          if ((allowedByFollowedAuthor || allowedBySelf) &&
              !allowedByLegacy &&
              hostedRoute == null) {
            await _ensureFollowedContext(activity);
          }

          await _applyActivity(activity, remoteNode.id);
          totalProcessed++;
        }

        currentCursor = delta.nextCursor;
        hasMore = delta.hasMore;
      }

      await _remoteNodeRepo.updateSyncCursor(
        remoteNode.id,
        currentCursor,
        syncTime,
      );
      for (final subscription in publicHostedSubscriptions) {
        await _hostedBoardRepo?.updateSubscriptionCursor(
          subscription.subscriptionId,
          currentCursor,
          syncTime,
        );
      }

      for (final subscription in protectedHostedSubscriptions) {
        final projection =
            hostedProjectionByBoardId[subscription.hostedBoardId];
        final authorize = _authorizeBoardRead;
        if (projection == null || authorize == null) {
          throw StateError('credential_required');
        }
        var boardCursor = subscription.syncCursor;
        var boardHasMore = true;
        while (boardHasMore) {
          final endpoint = Uri.parse(
            '${remoteClient.baseUrl}/api/v1/forum-host/boards/'
            '${Uri.encodeComponent(subscription.hostedBoardId)}/ops/delta',
          );
          final proofHeaders = await authorize(projection, endpoint);
          final deltaJson = await remoteClient.getBoardDelta(
            boardId: subscription.hostedBoardId,
            proofHeaders: proofHeaders,
            cursor: boardCursor > 0 ? boardCursor : null,
            limit: 100,
          );
          final trusted = await _trustedActivities(deltaJson);
          final readable =
              projection.contentVisibility == 'end_to_end_encrypted'
              ? await _decryptPrivateActivities(trusted, projection)
              : trusted;
          await _captureAuthorTiers(readable);
          final delta = DeltaResponse.fromJson({
            ...deltaJson,
            'activities': readable,
          });
          for (final entry in delta.activities) {
            final route = _routeHostedActivity(
              entry.activity,
              hostedSubscriptionByBoardId,
              hostedProjectionByBoardId,
            );
            if (route == null ||
                route.subscription.subscriptionId !=
                    subscription.subscriptionId) {
              continue;
            }
            await _notificationProjector?.onSyncedActivity(entry.activity);
            if (!_isWithinRetention(
              route.activity,
              subscription.retentionDays,
              syncTime,
            )) {
              continue;
            }
            await _applyActivity(route.activity, remoteNode.id);
            totalProcessed++;
          }
          boardCursor = delta.nextCursor;
          boardHasMore = delta.hasMore;
        }
        await _hostedBoardRepo?.updateSubscriptionCursor(
          subscription.subscriptionId,
          boardCursor,
          syncTime,
        );
      }

      if (needsSelfBackfill) {
        await _selfBackfillState.markComplete(
          remoteNodeId: remoteNode.id,
          did: localDid,
        );
      }

      return SyncResult.success(
        activitiesProcessed: totalProcessed,
        newCursor: currentCursor,
      );
    } catch (e) {
      return SyncResult.failure(errorMessage: e.toString());
    }
  }

  bool _requiresBoardCapability(HostedBoardProjection projection) {
    if (projection.contentVisibility != 'public') return true;
    final read = projection.accessPolicy['read'];
    return read is Map && read['requirement'] != 'public';
  }

  Future<List<dynamic>> _trustedActivities(
    Map<String, dynamic> deltaJson,
  ) async {
    final activities = deltaJson['activities'];
    if (activities is! List<dynamic>) return const [];
    final trusted = <dynamic>[];
    for (final raw in activities) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      if (await _opSignatureVerifier.isTrusted(entry)) {
        trusted.add(entry);
      }
    }
    return trusted;
  }

  Future<List<dynamic>> _decryptPrivateActivities(
    List<dynamic> activities,
    HostedBoardProjection board,
  ) async {
    if (board.encryptionState != 'ready' || board.encryptionEpoch < 1) {
      throw const PrivateBoardCryptoException('private_board_not_ready');
    }
    final result = <dynamic>[];
    for (final raw in activities) {
      if (raw is! Map) {
        throw const PrivateBoardCryptoException('invalid_private_activity');
      }
      final entry = Map<String, dynamic>.from(raw);
      final activityRaw = entry['activity'];
      if (activityRaw is! Map) {
        throw const PrivateBoardCryptoException('invalid_private_activity');
      }
      final activity = Map<String, dynamic>.from(activityRaw);
      final entityType = activity['entityType'];
      if (entityType != 'thread' && entityType != 'post') {
        result.add(entry);
        continue;
      }
      final payloadRaw = activity['payload'];
      final payload = payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : <String, dynamic>{};
      final envelopeRaw = payload['private_envelope'];
      if (envelopeRaw is! Map) {
        throw const PrivateBoardCryptoException('missing_content_envelope');
      }
      final envelope = PrivateBoardContentEnvelope.fromJson(
        Map<String, Object?>.from(envelopeRaw),
      );
      if (envelope.boardId != board.hostedBoardId ||
          envelope.epoch != board.encryptionEpoch ||
          envelope.policyVersion != board.accessPolicyVersion ||
          envelope.recordId != activity['entityId'] ||
          envelope.recordType != entityType) {
        throw const PrivateBoardCryptoException('stale_content_envelope');
      }
      final clear = await _privateBoardCrypto.decryptContent(envelope);
      entry['activity'] = {
        ...activity,
        'createdAt': envelope.createdAt.toIso8601String(),
        'payload': {...payload, ...clear}..remove('private_envelope'),
      };
      result.add(entry);
    }
    return result;
  }

  _HostedActivityRoute? _routeHostedActivity(
    Activity activity,
    Map<String, BoardSubscription> subscriptionByHostedBoardId,
    Map<String, HostedBoardProjection> projectionByHostedBoardId,
  ) {
    if (subscriptionByHostedBoardId.isEmpty) return null;
    final hostedBoardId = _hostedBoardIdFor(activity);
    if (hostedBoardId == null) return null;
    final subscription = subscriptionByHostedBoardId[hostedBoardId];
    final projection = projectionByHostedBoardId[hostedBoardId];
    if (subscription == null || projection == null) return null;
    return _HostedActivityRoute(
      subscription: subscription,
      activity: _localProjectionActivity(activity, projection),
    );
  }

  String? _hostedBoardIdFor(Activity activity) {
    final raw = activity.entityType.toLowerCase() == 'board'
        ? (activity.boardId ?? activity.entityId)
        : activity.boardId;
    return _hostedBoardIdSuffix(raw);
  }

  /// Op boardIds are `<creator's ephemeral forum-host node id>_<hostedBoardId>`
  /// — the prefix is a per-install/per-device timestamp, so it differs across
  /// reinstalls and devices. Match hosted activities on the stable
  /// hosted_board_id suffix instead, so a pulled thread/post routes to the local
  /// board for the same hosted board regardless of who/which install created it.
  String? _hostedBoardIdSuffix(String? boardId) {
    if (boardId == null || boardId.isEmpty) return boardId;
    final underscore = boardId.indexOf('_');
    if (underscore < 0) return boardId;
    final suffix = boardId.substring(underscore + 1);
    return suffix.isEmpty ? boardId : suffix;
  }

  Activity _localProjectionActivity(
    Activity activity,
    HostedBoardProjection projection,
  ) {
    if (activity.entityType.toLowerCase() == 'board') {
      return Activity(
        activityId: activity.activityId,
        originNodeId: activity.originNodeId,
        type: activity.type,
        entityType: activity.entityType,
        entityId: projection.localBoardId,
        boardId: projection.localBoardId,
        threadId: activity.threadId,
        authorId: activity.authorId,
        createdAt: activity.createdAt,
        payload: {
          ...activity.payload,
          'slug': projection.localSlug,
          'title': projection.title,
          if (projection.description != null)
            'description': projection.description,
        },
      );
    }
    return Activity(
      activityId: activity.activityId,
      originNodeId: activity.originNodeId,
      type: activity.type,
      entityType: activity.entityType,
      entityId: activity.entityId,
      boardId: projection.localBoardId,
      threadId: activity.threadId,
      authorId: activity.authorId,
      createdAt: activity.createdAt,
      payload: activity.payload,
    );
  }

  Future<SyncResult> syncFromRemote(RelayApiClient remoteClient) async {
    final remoteNode = await _remoteNodeRepo.getActive();
    if (remoteNode == null) {
      return SyncResult.failure(
        errorMessage: 'No active remote node configured',
      );
    }
    return syncFromNode(remoteClient, remoteNode);
  }

  bool _isWithinRetention(Activity activity, int? retentionDays, DateTime now) {
    if (retentionDays == null) {
      return true;
    }
    final entityType = activity.entityType.toLowerCase();
    if (entityType != 'post' && entityType != 'thread') {
      return true;
    }
    final cutoff = now.toUtc().subtract(Duration(days: retentionDays));
    return !activity.createdAt.toUtc().isBefore(cutoff);
  }

  Future<void> _applyActivity(Activity activity, String sourceNodeId) async {
    if (activity.type.toLowerCase() == 'delete') {
      // A remote host controls only its own projection. It must never erase
      // the user's canonical local copy, including entity kinds this client
      // does not currently render (for example an account/profile tombstone).
      if (activity.entityType.toLowerCase() == 'reaction') {
        await _applyReactionDelete(activity);
      } else {
        await _recordRemoteDelete(activity, sourceNodeId);
      }
      return;
    }
    await _remoteTombstones?.remove(
      sourceNodeId,
      activity.entityType.toLowerCase(),
      activity.entityId,
    );
    switch (activity.entityType.toLowerCase()) {
      case 'board':
        await _applyBoardActivity(activity, sourceNodeId);
        break;
      case 'thread':
        await _applyThreadActivity(activity, sourceNodeId);
        break;
      case 'post':
        await _applyPostActivity(activity, sourceNodeId);
        break;
      case 'murmur':
      case 'note':
        await _applyContentItemActivity(activity, sourceNodeId);
        break;
      case 'comment':
        await _applyCommentActivity(activity, sourceNodeId);
        break;
      case 'reaction':
        await _applyReactionActivity(activity);
        break;
    }
  }

  Future<void> _applyReactionDelete(Activity activity) async {
    await _reactionRepo?.delete(activity.entityId);
  }

  /// Projects a signature-verified reaction into the local cache used by all
  /// Flutter surfaces (web, mobile, and desktop). The target must already be
  /// locally known and, when supplied, must agree with its signed board route;
  /// this prevents a reaction from being injected into an unrelated board.
  Future<void> _applyReactionActivity(Activity activity) async {
    final repo = _reactionRepo;
    if (repo == null) return;
    final payload = activity.payload;
    final targetTypeName = payload['targetType']?.toString();
    final targetId = payload['targetId']?.toString();
    final reactionTypeName = payload['reactionType']?.toString();
    if (targetTypeName == null ||
        targetId == null ||
        reactionTypeName == null ||
        targetId.isEmpty) {
      return;
    }

    final targetType = _reactionTargetType(targetTypeName);
    final reactionType = _reactionType(reactionTypeName);
    if (targetType == null || reactionType == null) return;

    final routedBoardId = activity.boardId;
    String? targetBoardId;
    switch (targetType) {
      case TargetType.thread:
        targetBoardId = (await _threadRepo.getById(targetId))?.boardId;
        // Standalone content historically uses the thread target kind too.
        // Preserve that wire compatibility while requiring it to be boardless.
        if (targetBoardId == null &&
            await _contentItemRepo?.getById(targetId) != null) {
          targetBoardId = '';
        }
        break;
      case TargetType.post:
        targetBoardId = (await _postRepo.getById(targetId))?.boardId;
        break;
    }
    if (targetBoardId == null ||
        (routedBoardId != null && routedBoardId != targetBoardId)) {
      return;
    }

    await repo.create(
      Reaction(
        id: activity.entityId,
        userId: activity.authorId,
        targetType: targetType,
        targetId: targetId,
        reactionType: reactionType,
        createdAt: activity.createdAt,
      ),
    );
  }

  TargetType? _reactionTargetType(String value) {
    for (final type in TargetType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  ReactionType? _reactionType(String value) {
    for (final type in ReactionType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  /// Ingests a comment on standalone content. Stored as a local post keyed by
  /// the target content id ([Activity.threadId]) so the content-detail screen
  /// reads it locally. Board-less, so it never surfaces as a forum thread.
  Future<void> _applyCommentActivity(
    Activity activity,
    String sourceNodeId,
  ) async {
    final payload = activity.payload;
    if (activity.type.toLowerCase() == 'delete') {
      await _recordRemoteDelete(activity, sourceNodeId);
      return;
    }
    final targetId =
        (payload['threadId'] ?? payload['targetId'])?.toString() ??
        activity.threadId;
    if (targetId == null || targetId.isEmpty) return;
    final now = DateTime.now();
    final post = Post(
      id: activity.entityId,
      threadId: targetId,
      boardId: '',
      authorId: activity.authorId,
      content: payload['content'] as String? ?? '',
      createdAt: activity.createdAt,
      updatedAt: now,
      lastEditAt: now,
      signatureVerified: true,
    );
    final existing = await _postRepo.getById(activity.entityId);
    if (existing == null) {
      await _postRepo.create(post);
    } else {
      await _postRepo.update(post);
    }
  }

  /// Reputation tiers are NOT trusted from federated ops.
  ///
  /// The `reputationTier` field travels OUTSIDE the op's signed payload
  /// (op_signature_payload covers author_did/entity_*/op_type/payload only) and
  /// is stamped by whichever relay serves the op. A modified or malicious
  /// self-hosted relay could therefore label any DID `verified_human` and have
  /// it sync in — forging "verified" humans. So we fail closed: a peer relay's
  /// tier claim never elevates a DID here.
  ///
  /// Verified status must instead be established by re-verifying an
  /// issuer-signed humanity attestation against a local issuer trust registry
  /// (trust flows from the issuer, not the relay). That re-verification path is
  /// the only thing allowed to write an elevated tier into the reputation repo.
  Future<void> _captureAuthorTiers(List<dynamic> trusted) async {
    final repo = _didReputationRepo;
    if (repo == null) return;
    // Fail closed: never write a peer-asserted tier (it's unsigned). Tiers
    // come only from the issuer-attestation re-verification path below —
    // the relay serves the issuer-signed VC, and WE re-verify the issuer's
    // Ed25519 proof against the pinned issuer key before believing it.
    final attestations = _issuerAttestations;
    if (attestations == null) return;

    final authorDids = <String>{};
    for (final raw in trusted) {
      if (raw is! Map) continue;
      final signed = raw['signedOp'];
      if (signed is! Map) continue;
      final did = signed['authorDid'];
      if (did is String && did.isNotEmpty) authorDids.add(did);
    }

    for (final did in authorDids) {
      // Per-DID verified results (incl. negatives) are cached inside the
      // service, so this stays cheap across sync batches.
      final tier = await attestations.verifiedTierFor(did);
      if (tier != null && tier.isNotEmpty) {
        await repo.put(did, tier);
      }
    }
  }

  Future<Set<String>> _resolveFollowedAuthorDids() async {
    final followRepo = _followRepo;
    final followerDid = _followerDid;
    if (followRepo == null || followerDid == null) return const {};
    final edges = await followRepo.listFollowing(
      followerDid,
      targetType: FollowTargetType.user,
    );
    final dids = <String>{};
    for (final edge in edges.where(
      (edge) => edge.status == FollowStatus.accepted,
    )) {
      final target = await followRepo.getTarget(edge.targetId);
      final did = target?.did ?? target?.canonicalUri;
      if (did != null && did.isNotEmpty) {
        dids.add(did);
      }
    }
    return dids;
  }

  Future<void> _ensureFollowedContext(Activity activity) async {
    final type = activity.entityType.toLowerCase();
    if (type != 'post' && type != 'thread') return;

    final boardId = activity.boardId;
    // Board-less posts are comments on standalone content (legacy comment ops
    // before the dedicated `comment` entity type). Never materialize a phantom
    // "Followed" board / "Untitled" thread for them — that leaked content
    // comments into 討論區 as fake forum threads.
    if (boardId == null || boardId.isEmpty) return;
    if (await _boardRepo.getById(boardId) == null) {
      await _boardRepo.create(
        Board(
          id: boardId,
          slug: await _uniqueBoardSlug(boardId, boardId),
          title: 'Followed',
          createdAt: activity.createdAt,
          updatedAt: _now(),
        ),
      );
    }

    if (type == 'post') {
      final threadId = activity.threadId;
      if (threadId != null && await _threadRepo.getById(threadId) == null) {
        await _threadRepo.create(
          Thread(
            id: threadId,
            boardId: boardId,
            title: 'Untitled',
            authorId: activity.authorId,
            createdAt: activity.createdAt,
            updatedAt: _now(),
          ),
        );
      }
    }
  }

  Future<void> _applyContentItemActivity(
    Activity activity,
    String sourceNodeId,
  ) async {
    final repo = _contentItemRepo;
    if (repo == null) return;

    if (activity.type.toLowerCase() == 'delete') {
      await _recordRemoteDelete(activity, sourceNodeId);
      return;
    }

    final mode = switch (activity.entityType.toLowerCase()) {
      'murmur' => ContentMode.murmur,
      'note' => ContentMode.note,
      _ => null,
    };
    if (mode == null) return;

    final payload = activity.payload;
    final visibility = _contentVisibilityFor(payload['visibility']);
    // Never store private content locally from the feed (fail-closed).
    if (visibility == ContentVisibility.private) return;

    final item = ContentItem(
      id: activity.entityId,
      authorDid: activity.authorId,
      mode: mode,
      body: payload['body'] as String? ?? '',
      status: ContentStatus.active,
      visibility: visibility,
      createdAt: activity.createdAt,
      updatedAt: _now(),
      title: payload['title'] as String?,
      publishedAt: _parseContentDate(payload['publishedAt']),
      localOnly: false,
      // Only signature-verified ops reach _applyActivity.
      signatureVerified: true,
    );

    final existing = await repo.getById(activity.entityId);
    if (existing == null) {
      await repo.create(item);
    } else {
      await repo.update(item);
    }
  }

  ContentVisibility _contentVisibilityFor(Object? value) {
    if (value is String) {
      try {
        return ContentVisibility.parse(value);
      } catch (_) {
        return ContentVisibility.public;
      }
    }
    return ContentVisibility.public;
  }

  DateTime? _parseContentDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  Future<void> _applyBoardActivity(
    Activity activity,
    String sourceNodeId,
  ) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _recordRemoteDelete(activity, sourceNodeId);
    } else {
      final now = DateTime.now();
      final existing = await _boardRepo.getById(activity.entityId);
      final slug = await _uniqueBoardSlug(
        payload['slug'] as String? ?? activity.entityId,
        activity.entityId,
      );
      final board = Board(
        id: activity.entityId,
        slug: slug,
        title: payload['title'] as String? ?? 'Untitled',
        description: payload['description'] as String?,
        createdAt: activity.createdAt,
        updatedAt: now,
        isDeleted: payload['isDeleted'] as bool? ?? false,
      );

      if (existing == null) {
        await _boardRepo.create(board);
      } else {
        await _boardRepo.update(board);
      }
    }
  }

  Future<String> _uniqueBoardSlug(String desiredSlug, String boardId) async {
    final base = desiredSlug.trim().isEmpty ? boardId : desiredSlug.trim();
    final boards = await _boardRepo.list();
    final usedByOtherId = {
      for (final board in boards)
        if (board.id != boardId) board.slug,
    };
    if (!usedByOtherId.contains(base)) return base;

    final suffix = _slugSuffix(boardId);
    var candidate = '$base-$suffix';
    var attempt = 2;
    while (usedByOtherId.contains(candidate)) {
      candidate = '$base-$suffix-$attempt';
      attempt += 1;
    }
    return candidate;
  }

  String _slugSuffix(String id) {
    final normalized = id
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isEmpty) return 'remote';
    if (normalized.length <= 12) return normalized;
    return normalized.substring(0, 12);
  }

  Future<void> _applyThreadActivity(
    Activity activity,
    String sourceNodeId,
  ) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _recordRemoteDelete(activity, sourceNodeId);
    } else {
      final now = DateTime.now();
      final thread = Thread(
        id: activity.entityId,
        boardId: activity.boardId!,
        title: payload['title'] as String? ?? 'Untitled',
        authorId: activity.authorId,
        createdAt: activity.createdAt,
        updatedAt: now,
        isDeleted: payload['isDeleted'] as bool? ?? false,
      );

      final existing = await _threadRepo.getById(activity.entityId);
      if (existing == null) {
        await _threadRepo.create(thread);
      } else {
        await _threadRepo.update(thread);
      }
    }
  }

  Future<void> _applyPostActivity(
    Activity activity,
    String sourceNodeId,
  ) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _recordRemoteDelete(activity, sourceNodeId);
    } else {
      final now = DateTime.now();
      DateTime? lastEditAt;
      if (payload['lastEditAt'] != null) {
        lastEditAt = DateTime.parse(payload['lastEditAt'] as String);
      }

      final post = Post(
        id: activity.entityId,
        threadId: activity.threadId!,
        boardId: activity.boardId!,
        authorId: activity.authorId,
        content: payload['content'] as String? ?? '',
        parentPostId: payload['parentPostId'] as String?,
        createdAt: activity.createdAt,
        updatedAt: now,
        lastEditAt: lastEditAt ?? now,
        isDeleted: payload['isDeleted'] as bool? ?? false,
        // Only signature-verified (trusted) ops reach _applyActivity.
        signatureVerified: true,
      );

      final existing = await _postRepo.getById(activity.entityId);
      if (existing == null) {
        await _postRepo.create(post);
      } else {
        await _postRepo.update(post);
      }
    }
  }

  Future<void> _recordRemoteDelete(
    Activity activity,
    String sourceNodeId,
  ) async {
    await _remoteTombstones?.upsert(
      RemoteTombstone(
        sourceNodeId: sourceNodeId,
        entityType: activity.entityType.toLowerCase(),
        entityId: activity.entityId,
        boardId: activity.boardId,
        authorDid: activity.payload['authorDid'] as String?,
        deletedByDid: activity.authorId,
        deletedAt: activity.createdAt,
        receivedAt: _now(),
      ),
    );
  }
}

class _HostedActivityRoute {
  final BoardSubscription subscription;
  final Activity activity;

  const _HostedActivityRoute({
    required this.subscription,
    required this.activity,
  });
}
