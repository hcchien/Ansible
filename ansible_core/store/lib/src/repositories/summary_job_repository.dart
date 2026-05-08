import '../entities/summary_job.dart';

abstract class SummaryJobRepository {
  Future<void> create(SummaryJob job);
  Future<SummaryJob?> getById(String id);
  Future<void> markCompleted(
    String id, {
    required String resultJson,
    required DateTime completedAt,
  });
}
