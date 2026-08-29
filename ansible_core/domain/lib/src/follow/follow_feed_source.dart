import 'content_item_feed_projector.dart';
import 'follow_feed_projector.dart';

/// A unified following-timeline item: either a board post or a standalone
/// murmur/note. Exposes a common [timestamp] and [reasons] for merge + render.
sealed class FollowTimelineItem {
  DateTime get timestamp;
  Set<FollowFeedReason> get reasons;
  bool get signatureVerified;
}

class PostTimelineItem extends FollowTimelineItem {
  final FollowFeedEntry entry;
  final String? authorDisplayName;
  final String? authorHandle;
  final int reactionCount;
  final int commentCount;

  PostTimelineItem(
    this.entry, {
    this.authorDisplayName,
    this.authorHandle,
    this.reactionCount = 0,
    this.commentCount = 0,
  });

  @override
  DateTime get timestamp => entry.post.lastEditAt;
  @override
  Set<FollowFeedReason> get reasons => entry.reasons;
  @override
  bool get signatureVerified => entry.post.signatureVerified;
}

class ContentTimelineItem extends FollowTimelineItem {
  final ContentFeedEntry entry;
  final String? authorDisplayName;
  final String? authorHandle;
  @override
  final bool signatureVerified;
  final int reactionCount;
  final int commentCount;

  ContentTimelineItem(
    this.entry, {
    this.signatureVerified = false,
    this.authorDisplayName,
    this.authorHandle,
    this.reactionCount = 0,
    this.commentCount = 0,
  });

  @override
  DateTime get timestamp => entry.item.publishedAt ?? entry.item.createdAt;
  @override
  Set<FollowFeedReason> get reasons => entry.reasons;
}

class FollowFeedPage {
  final List<FollowTimelineItem> items;

  /// Opaque continuation cursor (null when there is no further page). The local
  /// source uses an offset; the future AppView source uses a relay `log_id`.
  /// Callers MUST treat it as opaque and pass it back unchanged.
  final int? nextCursor;
  final bool hasMore;

  const FollowFeedPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });
}

/// Abstraction over how the following timeline is retrieved.
///
/// MVP implementation [LocalDeltaFilterSource] assembles the timeline from the
/// locally-synced store. A future `AppViewTimelineSource` will call the AppView
/// `POST /api/v1/timeline` for federated follows — a config/DI swap, not a
/// rewrite. The interface therefore must not assume local-only access.
abstract class FollowFeedSource {
  Future<FollowFeedPage> fetch({
    required String followerDid,
    int? cursor,
    int limit,
  });
}

/// MVP source: merges the local post and murmur/note projections into one
/// reverse-chronological timeline (Design 1 — local filter over synced ops).
class LocalDeltaFilterSource implements FollowFeedSource {
  final FollowFeedProjector postProjector;
  final ContentItemFeedProjector contentProjector;

  const LocalDeltaFilterSource({
    required this.postProjector,
    required this.contentProjector,
  });

  @override
  Future<FollowFeedPage> fetch({
    required String followerDid,
    int? cursor,
    int limit = 50,
  }) async {
    final posts = await postProjector.project(followerDid: followerDid);
    final content = await contentProjector.project(followerDid: followerDid);

    final merged = <FollowTimelineItem>[
      ...posts.map(PostTimelineItem.new),
      ...content.map(ContentTimelineItem.new),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final offset = cursor ?? 0;
    final pageItems = merged.skip(offset).take(limit).toList();
    final consumed = offset + pageItems.length;
    final hasMore = consumed < merged.length;

    return FollowFeedPage(
      items: pageItems,
      nextCursor: hasMore ? consumed : null,
      hasMore: hasMore,
    );
  }
}
