import 'dart:convert';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:http/http.dart' as http;

import '../config/protocol.dart';

/// HTTP client for the AppView timeline API. Its [fetch] matches the
/// `AppViewTimelineFetcher` typedef, so it plugs straight into
/// `AppViewTimelineSource`. (Client-side Ed25519 re-verification is a follow-up:
/// it requires the AppView to return the original signed payload + signature,
/// which feed_items does not yet store; today the app trusts the first-party
/// AppView's ingest-time verification, the same trust as the relay delta.)
class AppViewTimelineClient {
  final String baseUrl;
  final http.Client _client;

  AppViewTimelineClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// Fetches a board's curated external (fediverse) items from the committed
  /// AppView contract:
  /// `GET /api/v1/boards/:board_id/external?cursor=&limit=`.
  ///
  /// These items are NEVER verified Elix content (`sig_verified == false`,
  /// `reputation_tier == external_unverified`). The caller must already have
  /// confirmed BOTH gates (board.externalInclusion AND the user opt-in) before
  /// calling — this client does no gating itself (inbound-federation D4).
  Future<AppViewExternalPage> fetchBoardExternal(
    String boardId, {
    String? cursor,
    int limit = 50,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/boards/$boardId/external').replace(
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri, headers: AnsibleProtocol.headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AppView board external failed: ${response.statusCode}');
    }

    // Decode as UTF-8 explicitly: external content is real fediverse text
    // (often CJK), and http defaults `.body` to Latin-1 absent a charset.
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) {
          final m = Map<String, dynamic>.from(raw);
          return AppViewExternalItem(
            logId: m['log_id'],
            opId: m['op_id'] as String? ?? '',
            boardId: m['board_id'] as String? ?? boardId,
            content: m['content'] as String? ?? '',
            createdAt: m['created_at'] is String
                ? DateTime.tryParse(m['created_at'] as String)
                : null,
            externalActorUri: m['external_actor_uri'] as String? ?? '',
            externalInstance: m['external_instance'] as String? ?? '',
            complianceLevel: m['compliance_level'] as String? ?? 'unknown',
            reputationTier:
                m['reputation_tier'] as String? ?? 'external_unverified',
            origin: m['origin'] as String? ?? 'activitypub',
          );
        })
        .toList();

    return AppViewExternalPage(
      items: items,
      nextCursor: body['next_cursor'] as String?,
      hasMore: body['has_more'] as bool? ?? false,
    );
  }

  Future<AppViewTimelinePage> fetch({
    required List<String> dids,
    int? cursor,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/timeline',
    );
    final response = await _client.post(
      uri,
      headers: const {
        'content-type': 'application/json',
        ...AnsibleProtocol.headers,
      },
      body: jsonEncode({
        'dids': dids,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      }),
    );

    return _parse('timeline', response);
  }

  /// Fetches the reader's server-materialized home timeline (fan-out-on-write).
  /// Matches the `AppViewHomeFetcher` typedef. The app sends only its own DID;
  /// the AppView assembles the page from the reader's pre-built home timeline.
  Future<AppViewTimelinePage> fetchHome({
    required String readerDid,
    int? cursor,
    int limit = 50,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/home').replace(
      queryParameters: {
        'reader': readerDid,
        if (cursor != null) 'cursor': '$cursor',
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri, headers: AnsibleProtocol.headers);
    return _parse('home', response);
  }

  /// Fetches the newest public content used to fill a sparse home feed. The
  /// AppView applies the same signature, visibility, and deletion gates as its
  /// other timeline endpoints.
  Future<AppViewTimelinePage> fetchExplore({
    int? cursor,
    int limit = 50,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/explore').replace(
      queryParameters: {
        if (cursor != null) 'cursor': '$cursor',
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri, headers: AnsibleProtocol.headers);
    return _parse('explore', response);
  }

  /// Fetches comments threaded under [threadId] (a content/thread entity id) via
  /// `GET /api/v1/thread/:thread_id`. Used by the content-detail screen to show
  /// replies on a standalone murmur/note.
  Future<AppViewTimelinePage> fetchThread({
    required String threadId,
    int? cursor,
    int limit = 100,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri =
        Uri.parse(
          '$base/api/v1/thread/${Uri.encodeComponent(threadId)}',
        ).replace(
          queryParameters: {
            if (cursor != null) 'cursor': '$cursor',
            'limit': '$limit',
          },
        );
    final response = await _client.get(uri, headers: AnsibleProtocol.headers);
    return _parse('thread', response);
  }

  AppViewTimelinePage _parse(String label, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AppView $label failed: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) {
          final m = Map<String, dynamic>.from(raw);
          return AppViewTimelineItem(
            entityType: m['entity_type'] as String? ?? '',
            entityId: m['entity_id'] as String? ?? '',
            authorDid: m['author_did'] as String? ?? '',
            authorDisplayName:
                m['author_display_name'] as String? ??
                m['authorDisplayName'] as String?,
            authorHandle:
                m['author_handle'] as String? ?? m['authorHandle'] as String?,
            boardId: m['board_id'] as String?,
            threadId: m['thread_id'] as String?,
            visibility: m['visibility'] as String?,
            createdAt: m['created_at'] is String
                ? DateTime.tryParse(m['created_at'] as String)
                : null,
            payload: Map<String, dynamic>.from(
              (m['payload'] as Map?) ?? const {},
            ),
          );
        })
        .toList();

    return AppViewTimelinePage(
      items: items,
      nextCursor: body['next_cursor'] as int?,
      hasMore: body['has_more'] as bool? ?? false,
    );
  }
}

/// A single curated external (fediverse) item surfaced into a board. It is
/// honestly-labeled external content — never verified Elix content, never a
/// 真人 author (inbound-federation Constitution Review §5).
class AppViewExternalItem {
  const AppViewExternalItem({
    required this.opId,
    required this.boardId,
    required this.content,
    required this.externalActorUri,
    required this.externalInstance,
    required this.complianceLevel,
    this.logId,
    this.createdAt,
    this.reputationTier = 'external_unverified',
    this.origin = 'activitypub',
  });

  /// AppView log id (int in the contract, kept dynamic for robustness).
  final Object? logId;
  final String opId;
  final String boardId;
  final String content;
  final DateTime? createdAt;

  /// Remote actor URI, e.g. `https://g0v.social/users/somebody`.
  final String externalActorUri;

  /// Remote instance host, e.g. `g0v.social`.
  final String externalInstance;

  /// Assessed instance compliance: `compatible` for assessed allowlisted
  /// instances, else `unknown` (lower-ranked, surfaced as such).
  final String complianceLevel;

  /// Fixed external tier; never an Elix reputation tier.
  final String reputationTier;

  /// Source protocol, e.g. `activitypub`.
  final String origin;

  bool get isCompatible => complianceLevel == 'compatible';

  /// Best-effort actor handle (`@user@instance`) derived from the actor URI.
  String get actorHandle {
    final uri = Uri.tryParse(externalActorUri);
    if (uri == null) return externalActorUri;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = segments.isNotEmpty ? segments.last : uri.host;
    final instance = externalInstance.isNotEmpty ? externalInstance : uri.host;
    return '@$name@$instance';
  }
}

class AppViewExternalPage {
  const AppViewExternalPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<AppViewExternalItem> items;
  final String? nextCursor;
  final bool hasMore;
}
