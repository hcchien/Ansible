import 'dart:convert';

class Thread {
  final String id;
  final String boardId;
  final String title;
  final String authorId;
  final Map<String, Object?>? poll;
  final Map<String, Object?>? pollResults;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Thread({
    required this.id,
    required this.boardId,
    required this.title,
    required this.authorId,
    this.poll,
    this.pollResults,
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
      if (poll != null) 'poll': poll,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory Thread.fromJson(Map<String, dynamic> json) {
    final authorId =
        json['authorId'] as String? ?? json['authorDid'] as String?;
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
      poll: _parsePoll(json['poll']),
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

  static Map<String, Object?>? _parsePoll(Object? value) {
    if (value is! Map) return null;
    final options = value['options'];
    if (options is! List || options.length < 2 || options.length > 12) {
      return null;
    }
    final normalizedOptions = <Map<String, Object?>>[];
    for (final option in options) {
      if (option is! Map) return null;
      final id = option['id']?.toString().trim();
      final label = option['label']?.toString().trim();
      if (id == null || id.isEmpty || label == null || label.isEmpty)
        return null;
      normalizedOptions.add({'id': id, 'label': label});
    }
    final closesAt = value['closes_at'] ?? value['closesAt'];
    return {
      'options': normalizedOptions,
      if (closesAt is String && closesAt.isNotEmpty) 'closes_at': closesAt,
    };
  }

  static Map<String, Object?>? parsePollResults(Object? value) {
    if (value is! Map || value['options'] is! List) return null;
    final options = <Map<String, Object?>>[];
    for (final option in value['options'] as List) {
      if (option is! Map) return null;
      final id = option['id']?.toString().trim();
      final label = option['label']?.toString().trim();
      final votes = int.tryParse(option['votes']?.toString() ?? '');
      if (id == null ||
          id.isEmpty ||
          label == null ||
          label.isEmpty ||
          votes == null ||
          votes < 0)
        return null;
      options.add({'id': id, 'label': label, 'votes': votes});
    }
    if (options.length < 2 || options.length > 12) return null;
    final closesAt = value['closes_at'] ?? value['closesAt'];
    return {
      'options': options,
      if (closesAt is String && closesAt.isNotEmpty) 'closes_at': closesAt,
    };
  }

  static String? encodePoll(Map<String, Object?>? poll) {
    final normalized = _parsePoll(poll);
    return normalized == null ? null : jsonEncode(normalized);
  }

  static Map<String, Object?>? decodePoll(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return _parsePoll(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  static String? encodePollResults(Map<String, Object?>? results) {
    final normalized = parsePollResults(results);
    return normalized == null ? null : jsonEncode(normalized);
  }

  static Map<String, Object?>? decodePollResults(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return parsePollResults(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }
}
