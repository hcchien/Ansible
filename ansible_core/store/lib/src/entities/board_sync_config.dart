import 'board_subscription.dart';
import 'hosted_board_projection.dart';

class BoardSyncConfig {
  static const int defaultRetentionDays = 90;
  static const Object _unchanged = Object();

  final String id;
  final String remoteNodeId;
  final String boardId;
  final bool syncEnabled;
  final int? retentionDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  BoardSyncConfig({
    required this.id,
    required this.remoteNodeId,
    required this.boardId,
    this.syncEnabled = true,
    this.retentionDays = defaultRetentionDays,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'remoteNodeId': remoteNodeId,
      'boardId': boardId,
      'syncEnabled': syncEnabled,
      'retentionDays': retentionDays,
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
      retentionDays: json.containsKey('retentionDays')
          ? json['retentionDays'] as int?
          : defaultRetentionDays,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  BoardSyncConfig copyWith({
    String? id,
    String? remoteNodeId,
    String? boardId,
    bool? syncEnabled,
    Object? retentionDays = _unchanged,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoardSyncConfig(
      id: id ?? this.id,
      remoteNodeId: remoteNodeId ?? this.remoteNodeId,
      boardId: boardId ?? this.boardId,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      retentionDays: identical(retentionDays, _unchanged)
          ? this.retentionDays
          : retentionDays as int?,
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

extension BoardSyncConfigSubscriptionCompat on BoardSyncConfig {
  BoardSubscription? toBoardSubscription(HostedBoardProjection? projection) {
    if (projection == null) {
      return null;
    }
    if (projection.localBoardId != boardId ||
        projection.forumHostId != remoteNodeId) {
      return null;
    }
    return BoardSubscription(
      subscriptionId: '${remoteNodeId}_${projection.hostedBoardId}',
      forumHostId: projection.forumHostId,
      hostedBoardId: projection.hostedBoardId,
      localBoardId: projection.localBoardId,
      readEnabled: syncEnabled,
      writeEnabled: syncEnabled,
      syncCursor: projection.lastSeenCursor,
      retentionDays: retentionDays,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
