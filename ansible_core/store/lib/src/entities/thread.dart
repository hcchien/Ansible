class Thread {
  final String id;
  final String boardId;
  final String title;
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Thread({
    required this.id,
    required this.boardId,
    required this.title,
    required this.authorId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'boardId': boardId,
      'title': title,
      'authorId': authorId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory Thread.fromJson(Map<String, dynamic> json) {
    final authorId = json['authorId'] as String? ?? json['authorDid'] as String?;
    if (authorId == null || authorId.isEmpty) {
      throw ArgumentError('Thread authorId is required');
    }

    final boardId = json['boardId'] as String? ?? json['board_id'] as String?;
    if (boardId == null || boardId.isEmpty) {
      throw ArgumentError('Thread boardId is required');
    }

    return Thread(
      id: json['id'] as String,
      boardId: boardId,
      title: json['title'] as String,
      authorId: authorId,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['createdAt']),
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
