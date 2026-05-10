enum BoardPublicationSourceType {
  threadDraft,
  postDraft,
  contentItem;

  static BoardPublicationSourceType parse(String value) {
    return BoardPublicationSourceType.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown BoardPublicationSourceType "$value"');
      },
    );
  }
}

enum BoardPublicationMode {
  primary,
  crossPost,
  projection;

  static BoardPublicationMode parse(String value) {
    return BoardPublicationMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () =>
          throw ArgumentError('Unknown BoardPublicationMode "$value"'),
    );
  }
}

enum BoardPublicationStatus {
  pending,
  accepted,
  failed,
  rejected;

  static BoardPublicationStatus parse(String value) {
    return BoardPublicationStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown BoardPublicationStatus "$value"');
      },
    );
  }
}

class BoardPublicationTarget {
  final String targetId;
  final String localSourceId;
  final BoardPublicationSourceType sourceType;
  final String forumHostId;
  final String hostedBoardId;
  final BoardPublicationMode mode;
  final BoardPublicationStatus status;
  final String? remoteThreadId;
  final String? remotePostId;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BoardPublicationTarget({
    required this.targetId,
    required this.localSourceId,
    required this.sourceType,
    required this.forumHostId,
    required this.hostedBoardId,
    required this.mode,
    required this.status,
    this.remoteThreadId,
    this.remotePostId,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  BoardPublicationTarget copyWith({
    String? targetId,
    String? localSourceId,
    BoardPublicationSourceType? sourceType,
    String? forumHostId,
    String? hostedBoardId,
    BoardPublicationMode? mode,
    BoardPublicationStatus? status,
    String? remoteThreadId,
    String? remotePostId,
    String? error,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoardPublicationTarget(
      targetId: targetId ?? this.targetId,
      localSourceId: localSourceId ?? this.localSourceId,
      sourceType: sourceType ?? this.sourceType,
      forumHostId: forumHostId ?? this.forumHostId,
      hostedBoardId: hostedBoardId ?? this.hostedBoardId,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      remoteThreadId: remoteThreadId ?? this.remoteThreadId,
      remotePostId: remotePostId ?? this.remotePostId,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
