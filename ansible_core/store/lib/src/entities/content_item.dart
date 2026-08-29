enum ContentMode {
  murmur,
  note,
  post,
  discussion;

  static ContentMode parse(String value) {
    return ContentMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown ContentMode "$value"'),
    );
  }
}

enum ContentStatus {
  draft,
  active,
  archived,
  removed,
  rejected;

  static ContentStatus parse(String value) {
    return ContentStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown ContentStatus "$value"'),
    );
  }
}

enum ContentVisibility {
  private,
  followers,
  unlisted,
  public;

  static ContentVisibility parse(String value) {
    return ContentVisibility.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown ContentVisibility "$value"'),
    );
  }
}

class ContentItem {
  final String id;
  final String authorDid;
  final ContentMode mode;
  final String body;
  final ContentStatus status;
  final ContentVisibility visibility;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? subjectId;
  final String? title;
  final DateTime? publishedAt;
  final bool isDeleted;
  final bool localOnly;

  /// True once the content's authoring/publication operation has a valid
  /// signature. Kept on the local projection so offline UI never has to infer
  /// provenance from authorship or network state.
  final bool signatureVerified;

  const ContentItem({
    required this.id,
    required this.authorDid,
    required this.mode,
    required this.body,
    required this.status,
    required this.visibility,
    required this.createdAt,
    required this.updatedAt,
    this.subjectId,
    this.title,
    this.publishedAt,
    this.isDeleted = false,
    this.localOnly = true,
    this.signatureVerified = false,
  });

  ContentItem copyWith({
    ContentStatus? status,
    ContentVisibility? visibility,
    DateTime? updatedAt,
    DateTime? publishedAt,
    bool? isDeleted,
    bool? localOnly,
    bool? signatureVerified,
  }) => ContentItem(
    id: id,
    authorDid: authorDid,
    mode: mode,
    body: body,
    status: status ?? this.status,
    visibility: visibility ?? this.visibility,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    subjectId: subjectId,
    title: title,
    publishedAt: publishedAt ?? this.publishedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    localOnly: localOnly ?? this.localOnly,
    signatureVerified: signatureVerified ?? this.signatureVerified,
  );
}
