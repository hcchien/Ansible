class BoardSyncConfig {
  final String id;
  final String remoteNodeId;
  final String boardId;
  final bool syncEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  BoardSyncConfig({
    required this.id,
    required this.remoteNodeId,
    required this.boardId,
    this.syncEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'remoteNodeId': remoteNodeId,
      'boardId': boardId,
      'syncEnabled': syncEnabled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory BoardSyncConfig.fromJson(Map<String, dynamic> json) {
    return BoardSyncConfig(
      id: json['id'] as String,
      remoteNodeId: json['remoteNodeId'] as String,
      boardId: json['boardId'] as String,
      syncEnabled: json['syncEnabled'] as bool? ?? true,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  BoardSyncConfig copyWith({
    String? id,
    String? remoteNodeId,
    String? boardId,
    bool? syncEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoardSyncConfig(
      id: id ?? this.id,
      remoteNodeId: remoteNodeId ?? this.remoteNodeId,
      boardId: boardId ?? this.boardId,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
