import 'package:ansible_store/ansible_store.dart';

import 'content_item_feed_projector.dart';
import 'follow_feed_projector.dart';
import 'follow_feed_source.dart';

/// A verified timeline item returned by the AppView (already signature-checked by
/// the transport). Field names mirror the AppView `/api/v1/timeline` response.
class AppViewTimelineItem {
  final String entityType;
  final String entityId;
  final String authorDid;
  final String? canonicalAuthorDid;
  final String? authorDisplayName;
  final String? authorHandle;
  final String? boardId;
  final String? threadId;
  final String? visibility;
  final DateTime? createdAt;
  final Map<String, dynamic> payload;
  final int reactionCount;
  final int commentCount;

  const AppViewTimelineItem({
    required this.entityType,
    required this.entityId,
    required this.authorDid,
    required this.payload,
    this.canonicalAuthorDid,
    this.authorDisplayName,
    this.authorHandle,
    this.boardId,
    this.threadId,
    this.visibility,
    this.createdAt,
    this.reactionCount = 0,
    this.commentCount = 0,
  });
}

class AppViewTimelinePage {
  final List<AppViewTimelineItem> items;
  final int? nextCursor;
  final bool hasMore;

  const AppViewTimelinePage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });
}

/// Transport supplied by the app: performs the AppView HTTP call AND re-verifies
/// each item's Ed25519 signature + DID-key binding, returning only trusted items.
/// Keeping it injected lets the domain layer stay free of HTTP and crypto deps.
typedef AppViewTimelineFetcher =
    Future<AppViewTimelinePage> Function({
      required List<String> dids,
      int? cursor,
      int limit,
    });

/// Server-materialized home timeline fetch (fan-out-on-write). The AppView
/// assembles the page from the reader's pre-built home timeline, so the app only
/// sends its own DID instead of the full follow set.
typedef AppViewHomeFetcher =
    Future<AppViewTimelinePage> Function({
      required String readerDid,
      int? cursor,
      int limit,
    });

/// [FollowFeedSource] backed by the AppView timeline API (the scalable read
/// path). Queries all accepted user-follow DIDs (federated + native localOnly) —
/// the AppView serves content by DID regardless of how the follow federates.
/// Drop-in replacement for the local source behind the same interface.
class AppViewTimelineSource implements FollowFeedSource {
  final FollowRepository followRepository;
  final AppViewTimelineFetcher fetcher;

  /// When provided, the reader's server-materialized home timeline is used
  /// (fan-out-on-write): the app sends only its own DID and the AppView returns
  /// the pre-assembled page. Falls back to the [fetcher] (fan-out-on-read over
  /// the accepted local follow set) when the home request is unavailable or
  /// rejected, as well as when [homeFetcher] is null.
  final AppViewHomeFetcher? homeFetcher;

  const AppViewTimelineSource({
    required this.followRepository,
    required this.fetcher,
    this.homeFetcher,
  });

  @override
  Future<FollowFeedPage> fetch({
    required String followerDid,
    int? cursor,
    int limit = 50,
  }) async {
    final page = await _fetchPage(
      followerDid: followerDid,
      cursor: cursor,
      limit: limit,
    );
    final items = mapItems(page.items);

    return FollowFeedPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  Future<AppViewTimelinePage> _fetchPage({
    required String followerDid,
    required int? cursor,
    required int limit,
  }) async {
    final fetchHome = homeFetcher;
    if (fetchHome == null) {
      return _fetchForAcceptedFollows(
        followerDid: followerDid,
        cursor: cursor,
        limit: limit,
      );
    }

    try {
      return await fetchHome(
        readerDid: followerDid,
        cursor: cursor,
        limit: limit,
      );
    } catch (_) {
      return _fetchForAcceptedFollows(
        followerDid: followerDid,
        cursor: cursor,
        limit: limit,
      );
    }
  }

  Future<AppViewTimelinePage> _fetchForAcceptedFollows({
    required String followerDid,
    required int? cursor,
    required int limit,
  }) async {
    final dids = await _followDids(followerDid);
    if (dids.isEmpty) return const AppViewTimelinePage(items: []);
    return fetcher(dids: dids, cursor: cursor, limit: limit);
  }

  /// Maps any verified AppView page (home, timeline, or explore) into the
  /// common feed model. Keeping this here guarantees identical filtering of
  /// comments and unsupported entity types across all feed surfaces.
  List<FollowTimelineItem> mapItems(List<AppViewTimelineItem> rawItems) {
    final items = <FollowTimelineItem>[];
    for (final raw in rawItems) {
      final mapped = _toTimelineItem(raw);
      if (mapped != null) items.add(mapped);
    }
    return items;
  }

  Future<List<String>> _followDids(String followerDid) async {
    final edges = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.user,
    );
    final dids = <String>[];
    // Every accepted user follow, regardless of visibility. Native Elix follows
    // are localOnly (the target has no ActivityPub inbox), but the AppView still
    // serves their content by DID — restricting to `federated` here dropped them
    // entirely (there is no separate local source in AppView mode), so a freshly
    // followed native user produced an empty timeline.
    for (final edge in edges.where(
      (edge) => edge.status == FollowStatus.accepted,
    )) {
      final target = await followRepository.getTarget(edge.targetId);
      final did = target?.did ?? target?.canonicalUri;
      if (did != null && did.isNotEmpty) dids.add(did);
    }
    return dids;
  }

  FollowTimelineItem? _toTimelineItem(AppViewTimelineItem raw) {
    final created = raw.createdAt ?? DateTime.now().toUtc();
    switch (raw.entityType) {
      case 'post':
        // Board-less posts are comments on standalone content (threadId == the
        // content's entity id); they belong in the content-detail view, not as
        // top-level timeline cards — otherwise a comment shows as its own post.
        if (raw.boardId == null ||
            raw.boardId!.isEmpty ||
            raw.threadId == null) {
          return null;
        }
        final post = Post(
          id: raw.entityId,
          threadId: raw.threadId!,
          boardId: raw.boardId!,
          authorId: raw.authorDid,
          content: raw.payload['content'] as String? ?? '',
          createdAt: created,
          updatedAt: created,
          lastEditAt: created,
          signatureVerified: true,
        );
        final thread = Thread(
          id: raw.threadId!,
          boardId: raw.boardId!,
          title:
              raw.payload['title'] as String? ??
              raw.payload['threadTitle'] as String? ??
              'Untitled',
          authorId: raw.authorDid,
          createdAt: created,
          updatedAt: created,
        );
        return PostTimelineItem(
          FollowFeedEntry(
            post: post,
            thread: thread,
            board: null,
            reasons: const {FollowFeedReason.followedUser},
          ),
          authorDisplayName: raw.authorDisplayName,
          authorHandle: raw.authorHandle,
          reactionCount: raw.reactionCount,
          commentCount: raw.commentCount,
        );
      case 'murmur':
      case 'note':
        final mode = raw.entityType == 'note'
            ? ContentMode.note
            : ContentMode.murmur;
        final item = ContentItem(
          id: raw.entityId,
          authorDid: raw.authorDid,
          mode: mode,
          body: raw.payload['body'] as String? ?? '',
          status: ContentStatus.active,
          visibility: _visibility(raw.visibility),
          createdAt: created,
          updatedAt: created,
          title: raw.payload['title'] as String?,
          publishedAt: created,
          localOnly: false,
        );
        return ContentTimelineItem(
          ContentFeedEntry(
            item: item,
            reasons: const {FollowFeedReason.followedUser},
          ),
          authorDisplayName: raw.authorDisplayName,
          authorHandle: raw.authorHandle,
          signatureVerified: true,
          reactionCount: raw.reactionCount,
          commentCount: raw.commentCount,
        );
      default:
        return null;
    }
  }

  ContentVisibility _visibility(String? value) {
    if (value == null) return ContentVisibility.public;
    try {
      return ContentVisibility.parse(value);
    } catch (_) {
      return ContentVisibility.public;
    }
  }
}
