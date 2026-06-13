class HostedBoardProjection {
  final String localBoardId;
  final String forumHostId;
  final String hostedBoardId;
  final String canonicalBoardUri;
  final String remoteSlug;
  final String localSlug;
  final String title;
  final String? description;
  final Map<String, Object?> permissions;

  /// Host-declared posting policy, e.g. `{"min_post_tier": "verified_human"}`.
  /// Empty map ⇒ no gate (default).
  final Map<String, Object?> postingPolicy;
  final int lastSeenCursor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const HostedBoardProjection({
    required this.localBoardId,
    required this.forumHostId,
    required this.hostedBoardId,
    required this.canonicalBoardUri,
    required this.remoteSlug,
    required this.localSlug,
    required this.title,
    this.description,
    this.permissions = const {},
    this.postingPolicy = const {},
    this.lastSeenCursor = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  /// Minimum reputation tier required to post, or null when ungated.
  String? get minPostTier {
    final tier = postingPolicy['min_post_tier'];
    if (tier is String && tier.trim().isNotEmpty) return tier;
    return null;
  }

  /// True when the board owner invited curated external (fediverse) content
  /// into this board's view (inbound-federation design D4, set by 4a into the
  /// same `posting_policy` map). Mutually exclusive with [minPostTier] —
  /// a trust-gated 真人版 board never carries unverified external content
  /// (enforced host-side at the policy chokepoint).
  bool get externalInclusion => postingPolicy['external_inclusion'] == true;

  HostedBoardProjection copyWith({
    String? localBoardId,
    String? forumHostId,
    String? hostedBoardId,
    String? canonicalBoardUri,
    String? remoteSlug,
    String? localSlug,
    String? title,
    String? description,
    Map<String, Object?>? permissions,
    Map<String, Object?>? postingPolicy,
    int? lastSeenCursor,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return HostedBoardProjection(
      localBoardId: localBoardId ?? this.localBoardId,
      forumHostId: forumHostId ?? this.forumHostId,
      hostedBoardId: hostedBoardId ?? this.hostedBoardId,
      canonicalBoardUri: canonicalBoardUri ?? this.canonicalBoardUri,
      remoteSlug: remoteSlug ?? this.remoteSlug,
      localSlug: localSlug ?? this.localSlug,
      title: title ?? this.title,
      description: description ?? this.description,
      permissions: permissions ?? this.permissions,
      postingPolicy: postingPolicy ?? this.postingPolicy,
      lastSeenCursor: lastSeenCursor ?? this.lastSeenCursor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
