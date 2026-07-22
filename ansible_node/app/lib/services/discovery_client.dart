import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/protocol.dart';

/// An actor surfaced by discovery (suggestions or people search).
class DiscoveredActor {
  final String did;
  final String? handle;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final String? reputationTier;
  final int? followerCount;
  final int? mutualCount;
  final String? reason;

  const DiscoveredActor({
    required this.did,
    this.handle,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.reputationTier,
    this.followerCount,
    this.mutualCount,
    this.reason,
  });

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final h = handle?.trim();
    if (h != null && h.isNotEmpty) return h;
    return did;
  }

  factory DiscoveredActor.fromJson(Map<String, dynamic> m) => DiscoveredActor(
    did: m['did'] as String? ?? '',
    handle: m['handle'] as String?,
    displayName: m['display_name'] as String?,
    bio: m['bio'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    reputationTier: m['reputation_tier'] as String?,
    followerCount: m['follower_count'] as int?,
    mutualCount: m['mutual_count'] as int?,
    reason: m['reason'] as String?,
  );
}

/// A board surfaced by board discovery/search (relay forum-host).
class BoardSearchResult {
  final String hostedBoardId;
  final String? slug;
  final String title;
  final String? description;
  final String? canonicalBoardUri;
  final List<String> tags;

  /// Host-declared posting policy, e.g. `{"min_post_tier": "verified_human"}`.
  final Map<String, Object?> postingPolicy;
  final Map<String, Object?> accessPolicy;
  final int accessPolicyVersion;
  final String contentVisibility;
  final int encryptionEpoch;
  final String encryptionState;
  final Map<String, Object?> federationPolicy;

  const BoardSearchResult({
    required this.hostedBoardId,
    required this.title,
    this.slug,
    this.description,
    this.canonicalBoardUri,
    this.tags = const [],
    this.postingPolicy = const {},
    this.accessPolicy = const {},
    this.accessPolicyVersion = 1,
    this.contentVisibility = 'public',
    this.encryptionEpoch = 0,
    this.encryptionState = 'disabled',
    this.federationPolicy = const {'mode': 'enabled'},
  });

  /// Minimum reputation tier required to post, or null when ungated.
  String? get minPostTier {
    final tier = postingPolicy['min_post_tier'];
    if (tier is String && tier.trim().isNotEmpty) return tier;
    return null;
  }

  factory BoardSearchResult.fromJson(Map<String, dynamic> m) =>
      BoardSearchResult(
        hostedBoardId: m['hosted_board_id'] as String? ?? '',
        slug: m['slug'] as String?,
        title: m['title'] as String? ?? '',
        description: m['description'] as String?,
        canonicalBoardUri: m['canonical_board_uri'] as String?,
        tags: (m['tags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        postingPolicy: Map<String, Object?>.from(
          (m['posting_policy'] as Map?) ?? const {},
        ),
        accessPolicy: Map<String, Object?>.from(
          (m['access_policy'] as Map?) ?? const {},
        ),
        accessPolicyVersion: m['access_policy_version'] as int? ?? 1,
        contentVisibility: m['content_visibility'] as String? ?? 'public',
        encryptionEpoch: m['encryption_epoch'] as int? ?? 0,
        encryptionState: m['encryption_state'] as String? ?? 'disabled',
        federationPolicy: Map<String, Object?>.from(
          (m['federation_policy'] as Map?) ?? const {'mode': 'enabled'},
        ),
      );
}

/// A content item surfaced by explore or search.
class DiscoveredPost {
  final String entityType;
  final String entityId;
  final String authorDid;
  final String? visibility;
  final String? reputationTier;

  /// Forum routing context (present for `post` entities; null for note/murmur),
  /// so a discovered post can deep-link to its thread instead of just the author.
  final String? boardId;
  final String? threadId;
  final Map<String, dynamic> payload;

  const DiscoveredPost({
    required this.entityType,
    required this.entityId,
    required this.authorDid,
    required this.payload,
    this.visibility,
    this.reputationTier,
    this.boardId,
    this.threadId,
  });

  String get body => (payload['body'] ?? payload['content'] ?? '').toString();

  /// True when this is a forum post that can be opened as a thread.
  bool get isThreadPost =>
      (threadId != null && threadId!.isNotEmpty) &&
      (boardId != null && boardId!.isNotEmpty);

  factory DiscoveredPost.fromJson(Map<String, dynamic> m) {
    final payload = Map<String, dynamic>.from(
      (m['payload'] as Map?) ?? const {},
    );
    String? str(Object? v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return DiscoveredPost(
      entityType: m['entity_type'] as String? ?? '',
      entityId: m['entity_id'] as String? ?? '',
      authorDid: m['author_did'] as String? ?? '',
      visibility: m['visibility'] as String?,
      reputationTier: m['reputation_tier'] as String?,
      // Top-level board_id/thread_id, falling back to the payload's camelCase.
      boardId: str(m['board_id']) ?? str(payload['boardId']),
      threadId: str(m['thread_id']) ?? str(payload['threadId']),
      payload: payload,
    );
  }
}

/// Result of a unified search.
class SearchResults {
  final List<DiscoveredActor> actors;
  final List<DiscoveredPost> posts;
  final List<BoardSearchResult> boards;

  const SearchResults({
    this.actors = const [],
    this.posts = const [],
    this.boards = const [],
  });
}

/// HTTP client for discovery endpoints. People + content come from the AppView;
/// boards come from the relay (which owns board metadata).
class DiscoveryClient {
  final String appViewBaseUrl;
  final String relayBaseUrl;
  final http.Client _client;

  DiscoveryClient({
    required this.appViewBaseUrl,
    required this.relayBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  bool get appViewEnabled => appViewBaseUrl.trim().isNotEmpty;

  Uri _appView(String path, [Map<String, String>? query]) => Uri.parse(
    '${_trim(appViewBaseUrl)}$path',
  ).replace(queryParameters: query);

  Uri _relay(String path, [Map<String, String>? query]) =>
      Uri.parse('${_trim(relayBaseUrl)}$path').replace(queryParameters: query);

  /// Who-to-follow suggestions for [readerDid].
  Future<List<DiscoveredActor>> suggestFollows({
    required String readerDid,
    int limit = 20,
  }) async {
    if (!appViewEnabled) return const [];
    final res = await _client.get(
      _appView('/api/v1/suggest/follows', {
        'reader': readerDid,
        'limit': '$limit',
      }),
      headers: AnsibleProtocol.headers,
    );
    return _actorList(_decode(res, 'suggest/follows')['items']);
  }

  /// Global newest-first public feed.
  Future<List<DiscoveredPost>> explore({int? cursor, int limit = 50}) async {
    if (!appViewEnabled) return const [];
    final res = await _client.get(
      _appView('/api/v1/explore', {
        if (cursor != null) 'cursor': '$cursor',
        'limit': '$limit',
      }),
      headers: AnsibleProtocol.headers,
    );
    return _postList(_decode(res, 'explore')['items']);
  }

  /// Unified people + content search (AppView) plus board search (relay).
  Future<SearchResults> search({required String query, int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const SearchResults();

    // AppView and Relay are independent discovery sources. One projection
    // being temporarily unavailable must not erase valid results from the
    // other source.
    final results = await Future.wait([
      _searchPeopleAndPosts(q, limit).onError((_, _) => const SearchResults()),
      searchBoards(
        query: q,
        limit: limit,
      ).onError((_, _) => const <BoardSearchResult>[]),
    ]);

    final peoplePosts = results[0] as SearchResults;
    final boards = results[1] as List<BoardSearchResult>;
    return SearchResults(
      actors: peoplePosts.actors,
      posts: peoplePosts.posts,
      boards: boards,
    );
  }

  Future<SearchResults> _searchPeopleAndPosts(String q, int limit) async {
    if (!appViewEnabled) return const SearchResults();
    final res = await _client.get(
      _appView('/api/v1/search', {'q': q, 'limit': '$limit'}),
      headers: AnsibleProtocol.headers,
    );
    final body = _decode(res, 'search');
    return SearchResults(
      actors: _actorList(body['actors']),
      posts: _postList(body['posts']),
    );
  }

  /// Board search/browse from the relay forum-host.
  Future<List<BoardSearchResult>> searchBoards({
    required String query,
    int limit = 20,
  }) async {
    final res = await _client.get(
      _relay('/api/v1/discover/boards', {'q': query.trim(), 'limit': '$limit'}),
      headers: AnsibleProtocol.headers,
    );
    final body = _decode(res, 'discover/boards');
    return (body['boards'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => BoardSearchResult.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  List<DiscoveredActor> _actorList(dynamic raw) =>
      (raw as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => DiscoveredActor.fromJson(Map<String, dynamic>.from(m)))
          .toList();

  List<DiscoveredPost> _postList(dynamic raw) =>
      (raw as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => DiscoveredPost.fromJson(Map<String, dynamic>.from(m)))
          .toList();

  Map<String, dynamic> _decode(http.Response res, String label) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Discovery $label failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _trim(String url) => url.replaceAll(RegExp(r'/+$'), '');
}
