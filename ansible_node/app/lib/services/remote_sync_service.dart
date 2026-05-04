import 'dart:convert';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;

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
      '$baseUrl/api/v1/sync/delta',
    ).replace(queryParameters: query);
    final response = await _client.get(uri, headers: authHeaders);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Relay delta failed: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, String> get authHeaders {
    final token = _accessToken;
    return {
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }
}

class RemoteSyncService {
  final RemoteNodeRepository _remoteNodeRepo;
  final BoardSyncConfigRepository _boardSyncConfigRepo;
  final BoardRepository _boardRepo;
  final ThreadRepository _threadRepo;
  final PostRepository _postRepo;
  final DateTime Function() _now;

  RemoteSyncService({
    required RemoteNodeRepository remoteNodeRepo,
    required BoardSyncConfigRepository boardSyncConfigRepo,
    required BoardRepository boardRepo,
    required ThreadRepository threadRepo,
    required PostRepository postRepo,
    DateTime Function()? now,
  }) : _remoteNodeRepo = remoteNodeRepo,
       _boardSyncConfigRepo = boardSyncConfigRepo,
       _boardRepo = boardRepo,
       _threadRepo = threadRepo,
       _postRepo = postRepo,
       _now = now ?? DateTime.now;

  Future<SyncResult> syncFromNode(
    RelayApiClient remoteClient,
    RemoteNode remoteNode,
  ) async {
    try {
      final enabledConfigs = await _boardSyncConfigRepo.listEnabledByRemote(
        remoteNode.id,
      );
      final enabledBoardIdSet = enabledConfigs.map((c) => c.boardId).toSet();
      if (enabledBoardIdSet.isEmpty) {
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
        final delta = DeltaResponse.fromJson(deltaJson);

        for (final entry in delta.activities) {
          final boardId = entry.activity.boardId;
          if (boardId == null || !enabledBoardIdSet.contains(boardId)) {
            continue;
          }
          if (!_isWithinRetention(
            entry.activity,
            retentionDaysByBoard[boardId],
            syncTime,
          )) {
            continue;
          }

          await _applyActivity(entry.activity);
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

      return SyncResult.success(
        activitiesProcessed: totalProcessed,
        newCursor: currentCursor,
      );
    } catch (e) {
      return SyncResult.failure(errorMessage: e.toString());
    }
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
    }
  }

  Future<void> _applyBoardActivity(Activity activity) async {
    final payload = activity.payload;
    final type = activity.type.toLowerCase();

    if (type == 'delete') {
      await _boardRepo.delete(activity.entityId);
    } else {
      final now = DateTime.now();
      final board = Board(
        id: activity.entityId,
        slug: payload['slug'] as String? ?? activity.entityId,
        title: payload['title'] as String? ?? 'Untitled',
        description: payload['description'] as String?,
        createdAt: activity.createdAt,
        updatedAt: now,
        isDeleted: payload['isDeleted'] as bool? ?? false,
      );

      final existing = await _boardRepo.getById(activity.entityId);
      if (existing == null) {
        await _boardRepo.create(board);
      } else {
        await _boardRepo.update(board);
      }
    }
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
