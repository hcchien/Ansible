import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

import 'op_signature_payload.dart';
import 'relay_identity_client.dart';

typedef RemoteOpEd25519Verifier =
    Future<bool> Function({
      required String publicKeyHex,
      required List<int> message,
      required String signatureHex,
    });

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
      headers: const {'content-type': 'application/json'},
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

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _normalizeDelta(body);
  }

  Map<String, String> get authHeaders {
    final token = _accessToken;
    return {
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _normalizeDelta(Map<String, dynamic> body) {
    final ops = body['ops'];
    if (ops is! List<dynamic>) return body;

    return {
      'activities': ops
          .map(
            (op) => _opToActivityLogEntry(Map<String, dynamic>.from(op as Map)),
          )
          .toList(),
      'nextCursor': body['next_cursor'] ?? body['nextCursor'] ?? 0,
      'hasMore': body['has_more'] ?? body['hasMore'] ?? false,
    };
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
      return {'rawPayload': payload};
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
  // Simple in-memory cache: did → verified public key hex
  final Map<String, String> _keyCache = {};

  RemoteOpSignatureVerifier({
    RemoteOpEd25519Verifier? verify,
    Future<String?> Function(String did)? resolvePublicKey,
  }) : _verify = verify ?? _verifyWithDidSigner,
       _resolvePublicKey = resolvePublicKey;

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
    if (!_isHex(publicKeyHex!, 64) || !_isHex(signature!, 128)) {
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
    final signatureValid = await _verify(
      publicKeyHex: publicKeyHex,
      message: utf8.encode(signingPayload),
      signatureHex: signature,
    );
    if (!signatureValid) return false;

    // Verify the public key is bound to authorDid (prevents relay from re-signing under arbitrary DIDs)
    final resolveKey = _resolvePublicKey;
    if (resolveKey != null) {
      final authorizedKey = _keyCache[authorDid] ?? await resolveKey(authorDid);
      if (authorizedKey == null) return false; // DID not registered
      if (authorizedKey.toLowerCase() != publicKeyHex.toLowerCase()) return false; // Key mismatch
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
  // Optional follow-aware ingestion: when a follow repository and the local
  // follower DID are provided, ops authored by followed users are retained even
  // when their board is not synced, and standalone murmur/note ops are folded
  // into the content item store. Null preserves the legacy board-only behavior.
  final FollowRepository? _followRepo;
  final ContentItemRepository? _contentItemRepo;
  final String? _followerDid;
  final RemoteOpSignatureVerifier _opSignatureVerifier;
  final DateTime Function() _now;

  RemoteSyncService({
    required RemoteNodeRepository remoteNodeRepo,
    required BoardSyncConfigRepository boardSyncConfigRepo,
    HostedBoardRepository? hostedBoardRepo,
    required BoardRepository boardRepo,
    required ThreadRepository threadRepo,
    required PostRepository postRepo,
    FollowRepository? followRepository,
    ContentItemRepository? contentItemRepo,
    String? followerDid,
    RemoteOpSignatureVerifier? opSignatureVerifier,
    RelayIdentityClient? identityClient,
    DateTime Function()? now,
  }) : _remoteNodeRepo = remoteNodeRepo,
       _boardSyncConfigRepo = boardSyncConfigRepo,
       _hostedBoardRepo = hostedBoardRepo,
       _boardRepo = boardRepo,
       _threadRepo = threadRepo,
       _postRepo = postRepo,
       _followRepo = followRepository,
       _contentItemRepo = contentItemRepo,
       _followerDid = followerDid,
       _opSignatureVerifier =
           opSignatureVerifier ??
           RemoteOpSignatureVerifier(
             resolvePublicKey: identityClient != null
                 ? (did) => identityClient.fetchPublicKey(did)
                 : null,
           ),
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
      final hostedSubscriptionByBoardId = {
        for (final subscription in hostedSubscriptions)
          subscription.hostedBoardId: subscription,
      };
      final enabledBoardIdSet = enabledConfigs.map((c) => c.boardId).toSet();
      final followedAuthorDids = await _resolveFollowedAuthorDids();
      if (requireBoardSyncConfig &&
          enabledBoardIdSet.isEmpty &&
          hostedSubscriptions.isEmpty &&
          followedAuthorDids.isEmpty) {
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
      int currentCursor = remoteNode.syncCursor;
      bool hasMore = true;
      final syncTime = _now();

      while (hasMore) {
        final deltaJson = await remoteClient.getDelta(
          cursor: currentCursor > 0 ? currentCursor : null,
          limit: 100,
        );
        final delta = DeltaResponse.fromJson({
          ...deltaJson,
          'activities': await _trustedActivities(deltaJson),
        });

        for (final entry in delta.activities) {
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
          if (requireBoardSyncConfig &&
              !allowedByLegacy &&
              hostedRoute == null &&
              !allowedByFollowedAuthor) {
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
          if (allowedByFollowedAuthor && !allowedByLegacy && hostedRoute == null) {
            await _ensureFollowedContext(activity);
          }

          await _applyActivity(activity);
          totalProcessed++;
        }

        currentCursor = delta.nextCursor;
        hasMore = delta.hasMore;
      }

      await _pruneExpiredPosts(enabledConfigs, syncTime);
      await _remoteNodeRepo.updateSyncCursor(
        remoteNode.id,
        currentCursor,
        syncTime,
      );
      for (final subscription in hostedSubscriptions) {
        await _hostedBoardRepo?.updateSubscriptionCursor(
          subscription.subscriptionId,
          currentCursor,
          syncTime,
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
    if (activity.entityType.toLowerCase() == 'board') {
      return activity.boardId ?? activity.entityId;
    }
    return activity.boardId;
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

  Future<void> _pruneExpiredPosts(
    List<BoardSyncConfig> enabledConfigs,
    DateTime now,
  ) async {
    for (final config in enabledConfigs) {
      final retentionDays = config.retentionDays;
      if (retentionDays == null) {
        continue;
      }
      final cutoff = now.toUtc().subtract(Duration(days: retentionDays));
      await _postRepo.deleteByBoardOlderThan(config.boardId, cutoff);
    }
  }

  Future<void> _applyActivity(Activity activity) async {
    switch (activity.entityType.toLowerCase()) {
      case 'board':
        await _applyBoardActivity(activity);
        break;
      case 'thread':
        await _applyThreadActivity(activity);
        break;
      case 'post':
        await _applyPostActivity(activity);
        break;
      case 'murmur':
      case 'note':
        await _applyContentItemActivity(activity);
        break;
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
    if (boardId != null && await _boardRepo.getById(boardId) == null) {
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
            boardId: boardId ?? threadId,
            title: 'Untitled',
            authorId: activity.authorId,
            createdAt: activity.createdAt,
            updatedAt: _now(),
          ),
        );
      }
    }
  }

  Future<void> _applyContentItemActivity(Activity activity) async {
    final repo = _contentItemRepo;
    if (repo == null) return;

    if (activity.type.toLowerCase() == 'delete') {
      await repo.delete(activity.entityId);
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

  Future<void> _applyBoardActivity(Activity activity) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _boardRepo.delete(activity.entityId);
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

  Future<void> _applyThreadActivity(Activity activity) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _threadRepo.delete(activity.entityId);
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

  Future<void> _applyPostActivity(Activity activity) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _postRepo.delete(activity.entityId);
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
      );

      final existing = await _postRepo.getById(activity.entityId);
      if (existing == null) {
        await _postRepo.create(post);
      } else {
        await _postRepo.update(post);
      }
    }
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
