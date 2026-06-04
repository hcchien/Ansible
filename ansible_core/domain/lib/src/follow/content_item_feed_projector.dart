import 'package:ansible_store/ansible_store.dart';

import 'follow_feed_projector.dart' show FollowFeedReason;

/// A single entry in the murmur/note following timeline.
class ContentFeedEntry {
  final ContentItem item;
  final Set<FollowFeedReason> reasons;

  const ContentFeedEntry({required this.item, required this.reasons});
}

/// Projects standalone short-form content (murmur/note) authored by followed
/// users into a reverse-chronological timeline.
///
/// Unlike [FollowFeedProjector] (board posts), murmur/note have no board/thread,
/// so the only inclusion reason is [FollowFeedReason.followedUser]. Only
/// non-deleted, non-private, active items are included; private content never
/// reaches this layer (it is fail-closed at publish time and never relayed).
class ContentItemFeedProjector {
  final FollowRepository followRepository;
  final ContentItemRepository contentItemRepository;

  const ContentItemFeedProjector({
    required this.followRepository,
    required this.contentItemRepository,
  });

  static const _feedModes = {ContentMode.murmur, ContentMode.note};

  Future<List<ContentFeedEntry>> project({required String followerDid}) async {
    final followedUserDids = await _resolveFollowedUserDids(followerDid);
    if (followedUserDids.isEmpty) return const [];

    final items = await contentItemRepository.list();
    final entries = <ContentFeedEntry>[];

    for (final item in items) {
      if (!_feedModes.contains(item.mode)) continue;
      if (item.isDeleted) continue;
      if (item.status != ContentStatus.active) continue;
      if (item.visibility == ContentVisibility.private) continue;
      if (!followedUserDids.contains(item.authorDid)) continue;

      entries.add(
        ContentFeedEntry(
          item: item,
          reasons: const {FollowFeedReason.followedUser},
        ),
      );
    }

    entries.sort((a, b) {
      final byTime = _sortKey(b.item).compareTo(_sortKey(a.item));
      if (byTime != 0) return byTime;
      return b.item.id.compareTo(a.item.id);
    });
    return entries;
  }

  DateTime _sortKey(ContentItem item) => item.publishedAt ?? item.createdAt;

  Future<Set<String>> _resolveFollowedUserDids(String followerDid) async {
    final edges = await followRepository.listFollowing(
      followerDid,
      targetType: FollowTargetType.user,
    );
    final dids = <String>{};
    for (final edge in edges.where(
      (edge) => edge.status == FollowStatus.accepted,
    )) {
      final target = await followRepository.getTarget(edge.targetId);
      final did = target?.did ?? target?.canonicalUri;
      if (did != null && did.isNotEmpty) {
        dids.add(did);
      }
    }
    return dids;
  }
}
