class RemoteNode {
  final String id;
  final String name;
  final String url;
  final String? accessToken;
  final int syncCursor;
  final DateTime? lastSyncAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  RemoteNode({
    required this.id,
    required this.name,
    required this.url,
    this.accessToken,
    this.syncCursor = 0,
    this.lastSyncAt,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'accessToken': accessToken,
      'syncCursor': syncCursor,
      'lastSyncAt': lastSyncAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory RemoteNode.fromJson(Map<String, dynamic> json) {
    return RemoteNode(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      accessToken: json['accessToken'] as String?,
      syncCursor: json['syncCursor'] as int? ?? 0,
      lastSyncAt: _parseNullableDate(json['lastSyncAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  RemoteNode copyWith({
    String? id,
    String? name,
    String? url,
    String? accessToken,
    int? syncCursor,
    DateTime? lastSyncAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return RemoteNode(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      accessToken: accessToken ?? this.accessToken,
      syncCursor: syncCursor ?? this.syncCursor,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
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

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value);
    }
    return null;
  }
}
