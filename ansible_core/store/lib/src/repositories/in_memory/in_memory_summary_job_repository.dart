import '../../entities/summary_job.dart';
import '../summary_job_repository.dart';

class InMemorySummaryJobRepository implements SummaryJobRepository {
  final Map<String, SummaryJob> _jobs = {};

  @override
  Future<void> create(SummaryJob job) async {
    _jobs[job.id] = job;
  }

  @override
  Future<SummaryJob?> getById(String id) async {
    return _jobs[id];
  }

  @override
  Future<void> markCompleted(
    String id, {
    required String resultJson,
    required DateTime completedAt,
  }) async {
    final job = _jobs[id];
    if (job == null) return;
    _jobs[id] = SummaryJob(
      id: job.id,
      requestedByDid: job.requestedByDid,
      contextPackId: job.contextPackId,
      providerConfigId: job.providerConfigId,
      summaryType: job.summaryType,
      status: SummaryJobStatus.completed,
      createdAt: job.createdAt,
      updatedAt: completedAt,
      resultJson: resultJson,
      errorMessage: job.errorMessage,
      completedAt: completedAt,
    );
  }
}
