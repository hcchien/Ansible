class BoardSubscription {
  final String subscriptionId;
  final String forumHostId;
  final String hostedBoardId;
  final String localBoardId;
  final bool readEnabled;
  final bool writeEnabled;
  final int syncCursor;
  final int? retentionDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BoardSubscription({
    required this.subscriptionId,
    required this.forumHostId,
    required this.hostedBoardId,
    required this.localBoardId,
    this.readEnabled = true,
    this.writeEnabled = false,
    this.syncCursor = 0,
    this.retentionDays,
    required this.createdAt,
    required this.updatedAt,
  });

  BoardSubscription copyWith({
    String? subscriptionId,
    String? forumHostId,
    String? hostedBoardId,
    String? localBoardId,
    bool? readEnabled,
    bool? writeEnabled,
    int? syncCursor,
    int? retentionDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoardSubscription(
      subscriptionId: subscriptionId ?? this.subscriptionId,
      forumHostId: forumHostId ?? this.forumHostId,
      hostedBoardId: hostedBoardId ?? this.hostedBoardId,
      localBoardId: localBoardId ?? this.localBoardId,
      readEnabled: readEnabled ?? this.readEnabled,
      writeEnabled: writeEnabled ?? this.writeEnabled,
      syncCursor: syncCursor ?? this.syncCursor,
      retentionDays: retentionDays ?? this.retentionDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
