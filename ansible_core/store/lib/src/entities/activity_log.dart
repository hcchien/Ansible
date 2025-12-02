class ActivityLog {
  final int? logId;
  final String activityId;
  final String? originNodeId;
  final String type;
  final String entityType;
  final String entityId;
  final String? boardId;
  final String? threadId;
  final String authorId;
  final DateTime createdAt;
  final String payload;
  final DateTime? insertedAt;

  ActivityLog({
    this.logId,
    required this.activityId,
    this.originNodeId,
    required this.type,
    required this.entityType,
    required this.entityId,
    this.boardId,
    this.threadId,
    required this.authorId,
    required this.createdAt,
    required this.payload,
    this.insertedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'logId': logId,
      'activityId': activityId,
      'originNodeId': originNodeId,
      'type': type,
      'entityType': entityType,
      'entityId': entityId,
      'boardId': boardId,
      'threadId': threadId,
      'authorId': authorId,
      'createdAt': createdAt.toIso8601String(),
      'payload': payload,
      'insertedAt': insertedAt?.toIso8601String(),
    };
  }

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      logId: json['logId'] as int?,
      activityId: json['activityId'] as String,
      originNodeId: json['originNodeId'] as String?,
      type: json['type'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      boardId: json['boardId'] as String?,
      threadId: json['threadId'] as String?,
      authorId: json['authorId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      payload: json['payload'] as String,
      insertedAt: json['insertedAt'] != null ? DateTime.parse(json['insertedAt'] as String) : null,
    );
  }
}
