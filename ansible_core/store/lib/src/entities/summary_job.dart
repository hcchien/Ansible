enum SummaryJobStatus {
  queued,
  running,
  completed,
  failed,
  discarded;

  static SummaryJobStatus parse(String value) {
    return SummaryJobStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown SummaryJobStatus "$value"'),
    );
  }
}

class SummaryJob {
  final String id;
  final String requestedByDid;
  final String contextPackId;
  final String providerConfigId;
  final String summaryType;
  final SummaryJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? resultJson;
  final String? errorMessage;
  final DateTime? completedAt;

  const SummaryJob({
    required this.id,
    required this.requestedByDid,
    required this.contextPackId,
    required this.providerConfigId,
    required this.summaryType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.resultJson,
    this.errorMessage,
    this.completedAt,
  });
}
