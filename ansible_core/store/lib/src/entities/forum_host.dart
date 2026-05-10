class ForumHost {
  final String forumHostId;
  final String displayName;
  final String baseUrl;
  final String canonicalHostUri;
  final String serverKind;
  final Map<String, Object?> capabilities;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ForumHost({
    required this.forumHostId,
    required this.displayName,
    required this.baseUrl,
    required this.canonicalHostUri,
    required this.serverKind,
    this.capabilities = const {},
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  ForumHost copyWith({
    String? forumHostId,
    String? displayName,
    String? baseUrl,
    String? canonicalHostUri,
    String? serverKind,
    Map<String, Object?>? capabilities,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ForumHost(
      forumHostId: forumHostId ?? this.forumHostId,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      canonicalHostUri: canonicalHostUri ?? this.canonicalHostUri,
      serverKind: serverKind ?? this.serverKind,
      capabilities: capabilities ?? this.capabilities,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
