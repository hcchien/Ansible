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
  });
}
