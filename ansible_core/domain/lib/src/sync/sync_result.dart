class SyncResult {
  final bool success;
  final int activitiesProcessed;
  final int newCursor;
  final String? errorMessage;
  final DateTime syncedAt;

  SyncResult({
    required this.success,
    required this.activitiesProcessed,
    required this.newCursor,
    this.errorMessage,
    required this.syncedAt,
  });

  factory SyncResult.success({
    required int activitiesProcessed,
    required int newCursor,
  }) {
    return SyncResult(
      success: true,
      activitiesProcessed: activitiesProcessed,
      newCursor: newCursor,
      syncedAt: DateTime.now(),
    );
  }

  factory SyncResult.failure({
    required String errorMessage,
    int activitiesProcessed = 0,
    int newCursor = 0,
  }) {
    return SyncResult(
      success: false,
      activitiesProcessed: activitiesProcessed,
      newCursor: newCursor,
      errorMessage: errorMessage,
      syncedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'activitiesProcessed': activitiesProcessed,
      'newCursor': newCursor,
      'errorMessage': errorMessage,
      'syncedAt': syncedAt.toIso8601String(),
    };
  }
}
