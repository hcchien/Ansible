import '../../entities/content_item.dart';
import '../../entities/transformation_job.dart';
import '../transformation_job_repository.dart';

class InMemoryTransformationJobRepository
    implements TransformationJobRepository {
  final Map<String, TransformationJob> _jobs = {};
  final Map<String, List<TransformationSource>> _sources = {};

  @override
  Future<void> addSource(TransformationSource source) async {
    final sources = _sources.putIfAbsent(source.transformationJobId, () => []);
    sources.removeWhere((item) => item.contentItemId == source.contentItemId);
    sources.add(source);
    sources.sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));
  }

  @override
  Future<void> create(TransformationJob job) async {
    _jobs[job.id] = job;
  }

  @override
  Future<TransformationJob?> getById(String id) async {
    return _jobs[id];
  }

  @override
  Future<List<TransformationSource>> listSources(String jobId) async {
    return List.unmodifiable(_sources[jobId] ?? const []);
  }

  @override
  Future<void> markAccepted(String id, {required DateTime acceptedAt}) async {
    final job = _jobs[id];
    if (job == null) return;
    _jobs[id] = _copyJob(
      job,
      status: TransformationJobStatus.accepted,
      updatedAt: acceptedAt,
    );
  }

  @override
  Future<void> markCompleted(
    String id, {
    required String outputSnapshotJson,
    required DateTime completedAt,
  }) async {
    final job = _jobs[id];
    if (job == null) return;
    _jobs[id] = _copyJob(
      job,
      status: TransformationJobStatus.completed,
      outputSnapshotJson: outputSnapshotJson,
      completedAt: completedAt,
      updatedAt: completedAt,
    );
  }

  TransformationJob _copyJob(
    TransformationJob job, {
    ContentMode? targetMode,
    TransformationJobStatus? status,
    String? outputSnapshotJson,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return TransformationJob(
      id: job.id,
      requestedByDid: job.requestedByDid,
      targetMode: targetMode ?? job.targetMode,
      providerType: job.providerType,
      status: status ?? job.status,
      createdAt: job.createdAt,
      updatedAt: updatedAt ?? job.updatedAt,
      promptProfile: job.promptProfile,
      inputSnapshotJson: job.inputSnapshotJson,
      outputSnapshotJson: outputSnapshotJson ?? job.outputSnapshotJson,
      errorMessage: job.errorMessage,
      completedAt: completedAt ?? job.completedAt,
    );
  }
}
