class Post {
  final String id;
  final String threadId;
  final String boardId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastEditAt;
  final String? parentPostId;
  final bool isDeleted;

  Post({
    required this.id,
    required this.threadId,
    required this.boardId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.lastEditAt,
    this.parentPostId,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'boardId': boardId,
      'authorId': authorId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastEditAt': lastEditAt.toIso8601String(),
      'parentPostId': parentPostId,
      'isDeleted': isDeleted,
    };
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    final authorId = json['authorId'] as String? ?? json['authorDid'] as String?;
    if (authorId == null || authorId.isEmpty) {
      throw ArgumentError('Post authorId is required');
    }

    final boardId = json['boardId'] as String? ?? json['board_id'] as String?;
    if (boardId == null || boardId.isEmpty) {
      throw ArgumentError('Post boardId is required');
    }

    return Post(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      boardId: boardId,
      authorId: authorId,
      content: json['content'] as String,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['createdAt']),
      lastEditAt: _parseDate(json['lastEditAt'] ?? json['updatedAt'] ?? json['createdAt']),
      parentPostId: json['parentPostId'] as String?,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) {
      return DateTime.now().toUtc();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value);
    }
    throw ArgumentError('Invalid date value "$value"');
  }
}
