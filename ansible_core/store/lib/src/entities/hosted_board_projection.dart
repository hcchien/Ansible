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
    this.lastSeenCursor = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

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
      lastSeenCursor: lastSeenCursor ?? this.lastSeenCursor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
