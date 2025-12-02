class Activity {
  final String activityId;
  final String? originNodeId;
  final String type;
  final String entityType;
  final String entityId;
  final String? boardId;
  final String? threadId;
  final String authorId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  Activity({
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
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      activityId: json['activityId'] as String,
      originNodeId: json['originNodeId'] as String?,
      type: json['type'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      boardId: json['boardId'] as String?,
      threadId: json['threadId'] as String?,
      authorId: json['authorId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activityId': activityId,
      'originNodeId': originNodeId,
      'type': type,
      'entityType': entityType,
      'entityId': entityId,
      'boardId': boardId,
      'threadId': threadId,
      'authorId': authorId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'payload': payload,
    };
  }
}

class ActivityLogEntry {
  final int logId;
  final Activity activity;

  ActivityLogEntry({
    required this.logId,
    required this.activity,
  });

  Map<String, dynamic> toJson() {
    return {
      'logId': logId,
      'activity': activity.toJson(),
    };
  }
}
