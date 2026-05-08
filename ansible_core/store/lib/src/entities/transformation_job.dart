import 'content_item.dart';
import 'ai_provider_config.dart';

enum TransformationJobStatus {
  drafting,
  queued,
  running,
  completed,
  failed,
  accepted,
  discarded;

  static TransformationJobStatus parse(String value) {
    return TransformationJobStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () =>
          throw ArgumentError('Unknown TransformationJobStatus "$value"'),
    );
  }
}

class TransformationJob {
  final String id;
  final String requestedByDid;
  final ContentMode targetMode;
  final AiProviderType providerType;
  final TransformationJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? promptProfile;
  final String? inputSnapshotJson;
  final String? outputSnapshotJson;
  final String? errorMessage;
  final DateTime? completedAt;

  const TransformationJob({
    required this.id,
    required this.requestedByDid,
    required this.targetMode,
    required this.providerType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.promptProfile,
    this.inputSnapshotJson,
    this.outputSnapshotJson,
    this.errorMessage,
    this.completedAt,
  });
}

class TransformationSource {
  final String transformationJobId;
  final String contentItemId;
  final int sourceOrder;

  const TransformationSource({
    required this.transformationJobId,
    required this.contentItemId,
    required this.sourceOrder,
  });
}
