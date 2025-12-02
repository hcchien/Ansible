class Board {
  final String id;
  final String slug;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Board({
    required this.id,
    required this.slug,
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory Board.fromJson(Map<String, dynamic> json) {
    final slug = (json['slug'] ?? json['path']) as String?;
    if (slug == null || slug.isEmpty) {
      throw ArgumentError('Board slug/path is required');
    }

    return Board(
      id: json['id'] as String,
      slug: slug,
      title: json['title'] as String,
      description: json['description'] as String?,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
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
